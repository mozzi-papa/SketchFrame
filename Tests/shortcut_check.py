"""검증용 창과 설정 화면에서 단축키를 검사하고 원래 설정을 복구합니다."""
import ctypes as c
import json
import subprocess
import statistics
import sys
import time
import native_check as n

CONTROL_OPTION = (1 << 18) | (1 << 19)
COMMAND = 1 << 20
SHIFT = 1 << 17
copy_pref = n.bind(n.cf, 'CFPreferencesCopyAppValue', [n.P, n.P], n.P)
set_pref = n.bind(n.cf, 'CFPreferencesSetAppValue', [n.P, n.P, n.P], None)
sync_pref = n.bind(n.cf, 'CFPreferencesAppSynchronize', [n.P], c.c_bool)
set_type = n.bind(n.cg, 'CGEventSetType', [n.P, c.c_uint32], None)


def key(code, flags=0, kind=None):
    for down in [True, False]:
        event = n.create_key(None, code, down)
        n.set_flags(event, flags)
        if kind is not None:
            set_type(event, kind)
        n.post(0, event)
        n.release(event)
        time.sleep(0.04)


def value(element, attribute):
    raw = n.get(element, attribute)
    result = n.text(raw) if raw else ''
    if raw:
        n.release(raw)
    return result


def find(element, label, depth=0):
    if depth > 12:
        return None
    if any(value(element, attribute) == label for attribute in ['AXTitle', 'AXDescription']):
        retain = n.bind(n.cf, 'CFRetain', [n.P], n.P)
        return retain(element)
    children = n.get(element, 'AXChildren')
    result = None
    if children:
        for index in range(n.array_count(children)):
            result = find(n.array_item(children, index), label, depth + 1)
            if result:
                break
        n.release(children)
    return result


def press(app, label):
    element = n.wait_for(lambda: find(app, label), '설정 항목이 없습니다: ' + label)
    action = n.string(None, b'AXPress', 0x08000100)
    try:
        assert n.perform_action(element, action) == 0, label
    finally:
        n.release(action)
        n.release(element)
    time.sleep(0.12)


def title(app, label):
    element = find(app, label)
    if not element:
        return ''
    result = value(element, 'AXTitle')
    n.release(element)
    return result


def settings(app, pid):
    bar = n.get(app, 'AXExtrasMenuBar')
    children = n.get(bar, 'AXChildren')
    action = n.string(None, b'AXPress', 0x08000100)
    # 메뉴가 열린 채로 반환되어 AXPress가 시간 초과를 보고할 수 있습니다.
    n.perform_action(n.array_item(children, 0), action)
    press(bar, '설정…')
    for raw in [action, children, bar]:
        n.release(raw)
    n.wait_for(lambda: n.frontmost_pid() == pid, '설정 창 활성화 실패')


def terminate(process):
    if process and process.poll() is None:
        process.terminate()
        process.wait(timeout=5)


def run(candidate_path, fixture_path):
    assert not subprocess.run(['pgrep', '-f', '/Applications/Rectangle.app/Contents/MacOS/Rectangle'], capture_output=True).stdout, 'Rectangle을 먼저 종료해 주세요.'
    domain = n.string(None, b'personal.windowsketch', 0x08000100)
    pref_key = n.string(None, b'shortcutBindings.v1', 0x08000100)
    original = copy_pref(pref_key, domain)
    event = n.create_event(None)
    pointer = n.event_location(event)
    n.release(event)
    original_app = n.frontmost_pid()
    candidate = fixture = app = None
    checks = []
    try:
        set_pref(pref_key, None, domain)
        assert sync_pref(domain)
        candidate = subprocess.Popen([candidate_path])
        n.wait_for(lambda: '켜짐 ·' in n.status(candidate.pid), '입력 연결 실패', 10)
        app = n.create_app(candidate.pid)
        n.set_timeout(app, 0.5)
        settings(app, candidate.pid)
        press(app, '가운데 절반 단축키')
        key(4, CONTROL_OPTION)
        n.wait_for(lambda: title(app, '가운데 절반 단축키') == '⌃⌥H', '단축키 기록 실패')
        press(app, '거의 최대화 단축키')
        key(4, CONTROL_OPTION)
        assert title(app, '거의 최대화 단축키') == '단축키를 누르세요…', '중복 단축키를 허용했습니다.'
        key(3, CONTROL_OPTION)
        n.wait_for(lambda: title(app, '거의 최대화 단축키') == '⌃⌥F', '중복 오류 후 재기록 실패')
        press(app, '자유 영역 그리기 단축키')
        for code, flags in [(59, 1 << 18), (58, CONTROL_OPTION), (56, CONTROL_OPTION | SHIFT),
                            (56, CONTROL_OPTION), (58, 1 << 18), (59, 0)]:
            key(code, flags, 12)
        n.wait_for(lambda: title(app, '자유 영역 그리기 단축키') == '⌃⌥⇧ + 왼쪽 드래그', '세 조합키 기록 실패')
        press(app, '왼쪽 절반 단축키 해제')
        assert title(app, '왼쪽 절반 단축키') == '단축키 입력'
        checks += ['설정 화면', '키 기록', '중복 차단과 재기록', '세 조합키 놓기', '해제']
        n.release(app)
        app = None
        terminate(candidate)
        candidate = subprocess.Popen([candidate_path])
        n.wait_for(lambda: '켜짐 ·' in n.status(candidate.pid), '재실행 입력 연결 실패', 10)
        app = n.create_app(candidate.pid)
        settings(app, candidate.pid)
        assert title(app, '가운데 절반 단축키') == '⌃⌥H'
        assert title(app, '왼쪽 절반 단축키') == '단축키 입력'
        assert title(app, '자유 영역 그리기 단축키') == '⌃⌥⇧ + 왼쪽 드래그'
        press(app, '전체 기본값 복원')
        assert title(app, '왼쪽 절반 단축키') == '⌃⌥←'
        assert title(app, '가운데 절반 단축키') == '단축키 입력'
        for label, code in [('가운데 절반 단축키', 4), ('거의 최대화 단축키', 3)]:
            press(app, label)
            key(code, CONTROL_OPTION)
        checks += ['재실행 후 설정 유지', '전체 기본값 복원']
        fixture = subprocess.Popen([fixture_path])
        n.wait_for(lambda: n.frame(fixture.pid), '검증 창 준비 실패')
        n.activate(fixture.pid)
        time.sleep(0.4)
        baseline = n.frame(fixture.pid)
        screen = json.loads(subprocess.check_output(['osascript', '-l', 'JavaScript', '-e',
            'ObjC.import("AppKit");var s=$.NSScreen.screens.objectAtIndex(0),f=s.frame,r=s.visibleFrame;JSON.stringify({x:r.origin.x,y:f.origin.y+f.size.height-r.origin.y-r.size.height,w:r.size.width,h:r.size.height,scale:s.backingScaleFactor,count:$.NSScreen.screens.count})'], text=True))
        screen['count'] = int(screen['count'])
        x,y,w,h = [screen[k] for k in ['x','y','w','h']]
        timings = []
        cases = [(123,0,(x,y,w/2,h)),(124,0,(x+w/2,y,w/2,h)),
                 (126,0,(x,y,w,h/2)),(125,0,(x,y+h/2,w,h/2)),
                 (32,0,(x,y,w/2,h/2)),(34,0,(x+w/2,y,w/2,h/2)),
                 (38,0,(x,y+h/2,w/2,h/2)),(40,0,(x+w/2,y+h/2,w/2,h/2)),
                 (4,0,(x+w/4,y,w/2,h)),(36,0,(x,y,w,h)),
                 (3,0,None),(126,SHIFT,None),(27,0,None),(24,0,None),(8,0,None),(51,0,baseline)]
        for code, extra, expected in cases:
            assert n.frontmost_pid() == fixture.pid, '활성 앱 변경으로 중단했습니다.'
            before = n.frame(fixture.pid)
            started = time.monotonic()
            key(code, CONTROL_OPTION | extra)
            if expected:
                n.wait_for(lambda: n.same_frame(n.frame(fixture.pid), expected) and '배치 요청 완료' in n.status(candidate.pid), '배치 불일치: '+str(code))
            else:
                action_title = {3:'거의 최대화',126:'높이 최대화',27:'작게',24:'크게',8:'가운데'}[code]
                n.wait_for(lambda: action_title in n.status(candidate.pid) and '배치 요청 완료' in n.status(candidate.pid), '배치 미적용: '+str(code))
                actual = n.frame(fixture.pid)
                if code == 8:
                    expected_center = (x+(w-before[2])/2,y+(h-before[3])/2,before[2],before[3])
                    assert all(abs(a-b) <= 0.5 for a,b in zip(actual, expected_center)), actual
                elif code == 126:
                    assert n.same_frame(actual, (before[0],y,before[2],h)), actual
                elif code in [27,24]:
                    delta = (-60 if code == 27 else 60)/screen['scale']
                    assert abs(actual[2]-min(w,before[2]+delta)) < 0.5, actual
                    assert abs(actual[3]-min(h,before[3]+delta)) < 0.5, actual
            timings.append((time.monotonic()-started)*1000)
            assert not n.visible_overlay(candidate.pid), '키보드 배치 중 오버레이가 표시됐습니다.'
            checks.append('창 배치 키 '+str(code)+'/'+str(extra))
        for code in [124,123]:
            assert n.frontmost_pid() == fixture.pid, '활성 앱 변경으로 중단했습니다.'
            key(code, CONTROL_OPTION | COMMAND)
            if screen['count'] == 1:
                n.wait_for(lambda: '이동할 다른 디스플레이가 없습니다' in n.status(candidate.pid), '단일 화면 안내 실패')
            else:
                time.sleep(0.5)
                assert '배치 요청 완료' in n.status(candidate.pid), n.status(candidate.pid)
        checks.append('디스플레이 이동 또는 단일 화면 안내')
        assert statistics.median(timings) < 400, ('키보드 배치 응답 지연', timings)
        assert n.frontmost_pid() == fixture.pid, '활성 앱 변경으로 중단했습니다.'
        key(123, CONTROL_OPTION)
        n.wait_for(lambda: n.same_frame(n.frame(fixture.pid), (x,y,w/2,h)), '크기 제한 검사 준비 실패')
        for _ in range(4):
            assert n.frontmost_pid() == fixture.pid, '활성 앱 변경으로 중단했습니다.'
            before_status = n.status(candidate.pid)
            key(27, CONTROL_OPTION)
            n.wait_for(lambda: n.status(candidate.pid) != before_status and '배치 요청 완료' in n.status(candidate.pid), '크기 제한 이후 요청 미완료')
        assert n.frame(fixture.pid)[2] == 799, n.frame(fixture.pid)
        assert not n.visible_overlay(candidate.pid), '지원하지 않는 키보드 크기에 오버레이가 표시됐습니다.'
        assert n.frontmost_pid() == fixture.pid, '활성 앱 변경으로 중단했습니다.'
        key(51, CONTROL_OPTION)
        n.wait_for(lambda: n.same_frame(n.frame(fixture.pid), baseline), '크기 제한을 거친 키보드 배치의 최초 복원 실패')
        checks += ['0.4초 고정 대기 제거', '크기 제한에도 키보드 오버레이 없음', '크기 제한 이후 최초 배치 복원']
        print(json.dumps({'result':'PASS','checks':checks,'screen':screen,'keyboardMilliseconds':{'median':round(statistics.median(timings),2),'maximum':round(max(timings),2)},'finalFrame':n.frame(fixture.pid)},ensure_ascii=False,indent=2))
    finally:
        for process in [candidate, fixture]:
            terminate(process)
        if app:
            n.release(app)
        set_pref(pref_key, original, domain)
        assert sync_pref(domain)
        for raw in [original, pref_key, domain]:
            if raw:
                n.release(raw)
        n.mouse(5, pointer)
        n.activate(original_app)


if __name__ == '__main__':
    run(*sys.argv[1:])
