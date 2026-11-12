"""실제 앱 대신 임시 폴더와 모의 명령으로 교체·복구 헬퍼를 검사합니다."""
from pathlib import Path
import os
import subprocess
import tempfile

source = Path('Source/UpdateInstaller.swift').read_text()
script = source.split('static let installScript = #"""\n', 1)[1].split('\n"""#', 1)[0]
mock = '''#!/usr/bin/python3
import os,pathlib,shutil,sys
root=pathlib.Path(os.environ['HELPER_ROOT']); case=os.environ['HELPER_CASE']
name=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]
if name=='kill': sys.exit(0 if case=='exit-timeout' else 1)
if name=='sleep' or name=='osascript': sys.exit(0)
if name=='open': sys.exit(1 if case=='launch-failure' and (pathlib.Path(args[0])/'marker').read_text()=='new' else 0)
if name=='mv':
 a,b=map(pathlib.Path,args)
 if case=='backup-failure' and a==root/'Sketch Frame.app': sys.exit(1)
 if case in ['replace-failure','restore-failure'] and a==root/'.work'/'SketchFrame.app': sys.exit(1)
 if case=='restore-failure' and a.name=='previous.app': sys.exit(1)
 shutil.move(str(a),str(b))
'''
for case in ['success','backup-failure','replace-failure','launch-failure','restore-failure','exit-timeout']:
    with tempfile.TemporaryDirectory(prefix="sketchframe helper '$ ") as directory:
        root=Path(directory)
        commands=root/'commands'; commands.mkdir()
        for name in ['mv','open','osascript','kill','sleep']:
            path=commands/name; path.write_text(mock); path.chmod(0o700)
        test_script=script
        for executable in ['/bin/mv','/usr/bin/open','/usr/bin/osascript','/bin/kill','/bin/sleep']:
            test_script=test_script.replace(executable, '"'+str(commands/Path(executable).name)+'"')
        current=root/'Sketch Frame.app'; current.mkdir(); (current/'marker').write_text('old')
        work=root/'.work'; work.mkdir()
        staged=work/'SketchFrame.app'; staged.mkdir(); (staged/'marker').write_text('new')
        package=root/'package'; package.mkdir()
        helper=package/'install.sh'; helper.write_text(test_script)
        result=subprocess.run(['/bin/sh',str(helper),'2147483000',str(current),str(staged),str(work/'previous.app'),str(work),str(package)],
            env={**os.environ,'HELPER_ROOT':str(root),'HELPER_CASE':case}, capture_output=True, text=True, timeout=20)
        if case=='success':
            assert result.returncode==0 and (current/'marker').read_text()=='new', result.stderr
        elif case=='restore-failure':
            assert result.returncode!=0 and (work/'previous.app'/'marker').read_text()=='old', result.stderr
            assert package.exists(), '복구 실패 자료를 지웠습니다.'
        else:
            assert result.returncode!=0 and (current/'marker').read_text()=='old', result.stderr
        if case!='restore-failure':
            assert not work.exists() and not package.exists(), case
        print('PASS:',case)
