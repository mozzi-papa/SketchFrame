"""검증용 창에서 실제 전역 드래그를 검사합니다. 사용자 창은 변경하지 않습니다."""
import argparse
import ctypes as c
import json
import re
import subprocess
import time

P = c.c_void_p
cf = c.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
ax = c.CDLL('/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices')
cg = c.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')


class Point(c.Structure):
    _fields_ = [('x', c.c_double), ('y', c.c_double)]


class Size(c.Structure):
    _fields_ = [('width', c.c_double), ('height', c.c_double)]


class Rect(c.Structure):
    _fields_ = [('origin', Point), ('size', Size)]


def bind(lib, name, args, result):
    function = getattr(lib, name)
    function.argtypes, function.restype = args, result
    return function


string = bind(cf, 'CFStringCreateWithCString', [P, c.c_char_p, c.c_uint32], P)
to_string = bind(cf, 'CFStringGetCString', [P, P, c.c_long, c.c_uint32], c.c_bool)
release = bind(cf, 'CFRelease', [P], None)
array_count = bind(cf, 'CFArrayGetCount', [P], c.c_long)
array_item = bind(cf, 'CFArrayGetValueAtIndex', [P, c.c_long], P)
dictionary_item = bind(cf, 'CFDictionaryGetValue', [P, P], P)
number_value = bind(cf, 'CFNumberGetValue', [P, c.c_int, P], c.c_bool)
create_app = bind(ax, 'AXUIElementCreateApplication', [c.c_int], P)
copy_attribute = bind(ax, 'AXUIElementCopyAttributeValue', [P, P, c.POINTER(P)], c.c_int)
set_timeout = bind(ax, 'AXUIElementSetMessagingTimeout', [P, c.c_float], c.c_int)
ax_value = bind(ax, 'AXValueGetValue', [P, c.c_int, P], c.c_bool)
create_event = bind(cg, 'CGEventCreate', [P], P)
event_location = bind(cg, 'CGEventGetLocation', [P], Point)
create_mouse = bind(cg, 'CGEventCreateMouseEvent', [P, c.c_uint32, Point, c.c_uint32], P)
create_key = bind(cg, 'CGEventCreateKeyboardEvent', [P, c.c_uint16, c.c_bool], P)
set_flags = bind(cg, 'CGEventSetFlags', [P, c.c_uint64], None)
post = bind(cg, 'CGEventPost', [c.c_uint32, P], None)
window_list = bind(cg, 'CGWindowListCopyWindowInfo', [c.c_uint32, c.c_uint32], P)
main_display = bind(cg, 'CGMainDisplayID', [], c.c_uint32)
display_bounds = bind(cg, 'CGDisplayBounds', [c.c_uint32], Rect)
MODIFIERS = (1 << 20) | (1 << 17)


def get(element, name):
    key = string(None, name.encode(), 0x08000100)
    value = P()
    error = copy_attribute(element, key, c.byref(value))
    release(key)
    return value.value if error == 0 else None


def text(value):
    buffer = c.create_string_buffer(8192)
    return buffer.value.decode() if to_string(value, buffer, len(buffer), 0x08000100) else ''


def status(pid):
    app = create_app(pid)
    set_timeout(app, 0.5)
    bar = get(app, 'AXExtrasMenuBar')
    children = get(bar, 'AXChildren') if bar else None
    result = ''
    if children:
        for i in range(array_count(children)):
            value = get(array_item(children, i), 'AXHelp')
            if value:
                result = text(value)
                release(value)
                break
        release(children)
    if bar:
        release(bar)
    release(app)
    return result


def element_frame(element):
    position, size = get(element, 'AXPosition'), get(element, 'AXSize')
    point, dimensions = Point(), Size()
    valid = position and size and ax_value(position, 1, c.byref(point)) and ax_value(size, 2, c.byref(dimensions))
    for value in [position, size]:
        if value:
            release(value)
    return (point.x, point.y, dimensions.width, dimensions.height) if valid else None


def frame(pid):
    app = create_app(pid)
    set_timeout(app, 0.5)
    window = get(app, 'AXFocusedWindow')
    result = element_frame(window) if window else None
    if window:
        release(window)
    release(app)
    return result


def preview_info(pid):
    def visit(element, depth=0):
        if depth > 5:
            return ''
        description = get(element, 'AXDescription')
        matches = description and text(description) == '선택 영역 미리보기'
        if description:
            release(description)
        if matches:
            value = get(element, 'AXValue')
            result = {'value': text(value), 'frame': element_frame(element)} if value else None
            if value:
                release(value)
            return result
        children = get(element, 'AXChildren')
        if children:
            for i in range(array_count(children)):
                result = visit(array_item(children, i), depth + 1)
                if result:
                    release(children)
                    return result
            release(children)
        return ''
    app = create_app(pid)
    set_timeout(app, 0.5)
    windows = get(app, 'AXWindows')
    result = ''
    if windows:
        for i in range(array_count(windows)):
            result = visit(array_item(windows, i))
            if result:
                break
        release(windows)
    release(app)
    return result


def preview(pid):
    info = preview_info(pid)
    return info['value'] if info else ''


def settled_preview(pid):
    previous = None
    stable = 0
    def settled():
        nonlocal previous, stable
        value = preview_info(pid)
        if value and value.get('frame') and value == previous:
            stable += 1
        else:
            stable = 0
        previous = value
        return value if stable >= 2 else None
    return wait_for(settled, '마지막 입력의 미리보기가 안정되지 않았습니다.')


def same_frame(actual, expected):
    return actual and expected and all(abs(a - b) < 0.5 for a, b in zip(actual, expected))


def visible_overlay(pid):
    def number(dictionary, name):
        key = string(None, name.encode(), 0x08000100)
        value = dictionary_item(dictionary, key)
        release(key)
        output = c.c_double()
        if value:
            number_value(value, 13, c.byref(output))
        return output.value
    windows = window_list(1 | 16, 0)
    if not windows:
        return False
    result = any(number(array_item(windows, i), 'kCGWindowOwnerPID') == pid and
                 number(array_item(windows, i), 'kCGWindowLayer') >= 100 for i in range(array_count(windows)))
    release(windows)
    return result


def wait_for(check, label, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.04)
    raise AssertionError(label)


def mouse(kind, point, flags=0):
    event = create_mouse(None, kind, point, 0)
    if not event:
        raise RuntimeError('마우스 검증 이벤트를 만들 수 없습니다.')
    set_flags(event, flags)
    post(0, event)
    release(event)


def frontmost_pid():
    return int(subprocess.check_output(['/usr/bin/osascript', '-l', 'JavaScript', '-e',
        'ObjC.import("AppKit");String($.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier)'], text=True).strip())


def hold_drag(start, end, target_pid):
    wait_for(lambda: frontmost_pid() == target_pid, '검증용 창이 활성 상태가 아니어서 입력을 중단했습니다.')
    mouse(5, start)
    mouse(1, start, MODIFIERS)
    time.sleep(0.06)
    for i in range(1, 13):
        if frontmost_pid() != target_pid:
            raise RuntimeError('활성 앱이 바뀌어 검증 입력을 중단했습니다.')
        mouse(6, Point(start.x + (end.x - start.x) * i / 12, start.y + (end.y - start.y) * i / 12), MODIFIERS)
        time.sleep(0.015)


def activate(pid):
    subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', '-e',
                    f'ObjC.import("AppKit");var a=$.NSRunningApplication.runningApplicationWithProcessIdentifier({int(pid)});a ? a.activateWithOptions(2) : false'],
                   check=True, capture_output=True)


def run(candidate_path, fixture_path):
    original_event = create_event(None)
    original_pointer = event_location(original_event)
    release(original_event)
    original_app = subprocess.check_output(['/usr/bin/osascript', '-l', 'JavaScript', '-e',
                                           'ObjC.import("AppKit");String($.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier)'], text=True).strip()
    candidate = fixture = None
    last_point = original_pointer
    try:
        candidate = subprocess.Popen([candidate_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        wait_for(lambda: '켜짐 ·' in status(candidate.pid), '검증 앱의 입력 감지가 연결되지 않았습니다.', 10)
        fixture = subprocess.Popen([fixture_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        wait_for(lambda: frame(fixture.pid), '검증용 창이 준비되지 않았습니다.')
        activate(fixture.pid)
        time.sleep(0.3)
        screen = json.loads(subprocess.check_output(['/usr/bin/osascript', '-l', 'JavaScript', '-e',
            'ObjC.import("AppKit");var s=$.NSScreen.screens.objectAtIndex(0);var f=s.frame;var r=s.visibleFrame;JSON.stringify({scale:s.backingScaleFactor,x:r.origin.x,y:f.origin.y+f.size.height-r.origin.y-r.size.height,width:r.size.width,height:r.size.height})'], text=True))
        bounds = Rect(Point(screen['x'], screen['y']), Size(screen['width'], screen['height']))
        scale = screen['scale']
        original_fixture_frame = frame(fixture.pid)
        start = Point(bounds.origin.x + 200, bounds.origin.y + 140)
        last_point = Point(start.x + 140, start.y + 110)
        hold_drag(start, last_point, fixture.pid)
        wait_for(lambda: visible_overlay(candidate.pid), '첫 드래그에서 미리보기가 표시되지 않았습니다.')
        initial_info = settled_preview(candidate.pid)
        assert same_frame(initial_info['frame'], (start.x, start.y, 140, 110)), initial_info
        assert f'{round(140 * scale)} × {round(110 * scale)} px' in initial_info['value'], initial_info
        assert '놓은 뒤 지원 여부를 확인합니다' in initial_info['value'], initial_info
        mouse(2, last_point)
        wait_for(lambda: '선택한 영역과 다르게 배치됐습니다.' in status(candidate.pid), '크기 제한 안내가 없습니다.')
        outcome = settled_preview(candidate.pid)
        applied = frame(fixture.pid)
        assert '경고: 앱의 크기 제한으로' in outcome['value'], outcome
        assert '복원' not in outcome['value'], outcome
        assert applied and same_frame(applied, (start.x, start.y, 799, 300)), applied
        assert same_frame(outcome['frame'], applied), (outcome, applied)
        assert f'실제 {round(799 * scale)} × {round(300 * scale)} px' in outcome['value'], outcome
        assert visible_overlay(candidate.pid), '경고가 화면에 표시되지 않았습니다.'
        assert not same_frame(applied, original_fixture_frame), '작은 영역 적용 후 이전 배치로 돌아갔습니다.'

        hold_drag(start, last_point, fixture.pid)
        second = settled_preview(candidate.pid)
        assert same_frame(second['frame'], initial_info['frame']), second
        assert '오류' not in second['value'], second
        assert '경고: 이 창에서 이전에 거부된 크기입니다' in second['value'], second
        time.sleep(3.1)
        assert visible_overlay(candidate.pid), '지난 오류 타이머가 새 드래그를 숨겼습니다.'
        for down in [True, False]:
            event = create_key(None, 53, down)
            set_flags(event, 0)
            post(0, event)
            release(event)
        wait_for(lambda: not visible_overlay(candidate.pid), 'Esc 취소 후 미리보기가 남았습니다.')
        mouse(2, last_point)
        assert same_frame(frame(fixture.pid), applied), 'Esc 취소가 창을 변경했습니다.'

        anchor_checks = []
        for reverse_x, reverse_y in [(False, False), (True, False), (False, True), (True, True)]:
            start = Point(bounds.origin.x + (bounds.size.width - 20 if reverse_x else 20),
                          bounds.origin.y + (bounds.size.height - 20 if reverse_y else 20))
            center_y = bounds.origin.y + bounds.size.height / 2
            last_point = Point(start.x + (-850 if reverse_x else 850), center_y + (12 if reverse_y else -12))
            expected = (min(start.x, last_point.x), min(start.y, last_point.y),
                        abs(last_point.x - start.x), abs(last_point.y - start.y))
            hold_drag(start, last_point, fixture.pid)
            info = settled_preview(candidate.pid)
            assert same_frame(info['frame'], expected), (info, expected)
            assert '자유 그리기' in info['value'], info
            mouse(2, last_point)
            wait_for(lambda: '배치 완료' in status(candidate.pid), '그린 크기로 배치되지 않았습니다.')
            assert same_frame(frame(fixture.pid), expected), (frame(fixture.pid), expected)
            anchor_checks.append({'reverseX': reverse_x, 'reverseY': reverse_y,
                                  'preview': info['frame'], 'actual': frame(fixture.pid)})

        start = Point(bounds.origin.x + bounds.size.width - 120, bounds.origin.y + bounds.size.height - 120)
        last_point = Point(start.x + 90, start.y + 90)
        before = frame(fixture.pid)
        hold_drag(start, last_point, fixture.pid)
        edge_info = settled_preview(candidate.pid)
        assert same_frame(edge_info['frame'], (start.x, start.y, 90, 90)), edge_info
        mouse(2, last_point)
        wait_for(lambda: '선택한 영역과 다르게 배치됐습니다.' in status(candidate.pid), '가장자리 크기 제한 안내가 없습니다.')
        edge_result = settled_preview(candidate.pid)
        assert '복원' not in edge_result['value'], edge_result
        assert same_frame(edge_result['frame'], frame(fixture.pid)), (edge_result, frame(fixture.pid))
        assert not same_frame(frame(fixture.pid), before), '가장자리 이동이 이전 배치로 복원됐습니다.'
        wait_for(lambda: not visible_overlay(candidate.pid), '실패 안내가 자동으로 닫히지 않았습니다.')
        result = status(candidate.pid)
        assert '시간 초과 0' in result, result
        maximum = re.search(r'입력 최대 ([\d.]+) ms', result)
        assert maximum and float(maximum[1]) < 50, result
        print(json.dumps({'result': 'PASS', 'checks': ['첫 드래그 표시', '작은 영역 좌표 보존',
                '미확인 크기 안내', '크기 제한 경고', '요청·실제 크기 안내', '이동 결과 유지', '이전 거부 크기 드래그 중 경고',
                '크기 자동 보정 없음', '오류 타이머와 새 드래그 분리',
                'Esc 취소', '네 방향 자유 그리기와 실제 배치 일치', '가장자리 보정 없음', '오류 안내 자동 닫기', '입력 시간 초과 없음'],
                'initialPreview': initial_info, 'outcome': outcome, 'anchorChecks': anchor_checks,
                'diagnostics': result}, ensure_ascii=False, indent=2))
    except Exception:
        if candidate:
            print('검증 실패 당시 상태:', status(candidate.pid))
        raise
    finally:
        # 검증 실패 시 남아 있는 드래그를 적용하지 않도록 입력 처리 프로세스부터 종료합니다.
        for process in [candidate, fixture]:
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            if process and process.stderr:
                process.stderr.close()
        mouse(2, last_point)
        mouse(5, original_pointer)
        activate(int(original_app))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate')
    parser.add_argument('fixture')
    args = parser.parse_args()
    run(args.candidate, args.fixture)
