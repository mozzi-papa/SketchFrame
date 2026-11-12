import AppKit

enum WindowAction: String, CaseIterable, Codable {
    case drawRegion, leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, almostMaximize, maximizeHeight, smaller, larger, center, restore, nextDisplay, previousDisplay

    static let leftColumn: [WindowAction] = [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf,
                                           .topLeft, .topRight, .bottomLeft, .bottomRight]
    static let rightColumn: [WindowAction] = [.maximize, .almostMaximize, .maximizeHeight, .smaller, .larger,
                                            .center, .restore, .nextDisplay, .previousDisplay]
    var title: String {
        switch self {
        case .drawRegion: return "자유 영역 그리기"
        case .leftHalf: return "왼쪽 절반"
        case .rightHalf: return "오른쪽 절반"
        case .centerHalf: return "가운데 절반"
        case .topHalf: return "위쪽 절반"
        case .bottomHalf: return "아래쪽 절반"
        case .topLeft: return "왼쪽 위"
        case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"
        case .bottomRight: return "오른쪽 아래"
        case .maximize: return "최대화"
        case .almostMaximize: return "거의 최대화"
        case .maximizeHeight: return "높이 최대화"
        case .smaller: return "작게"
        case .larger: return "크게"
        case .center: return "가운데"
        case .restore: return "복원"
        case .nextDisplay: return "다음 디스플레이"
        case .previousDisplay: return "이전 디스플레이"
        }
    }

    var defaultBinding: ShortcutBinding {
        let controlOption = CGEventFlags([.maskControl, .maskAlternate]).rawValue
        switch self {
        case .drawRegion: return ShortcutBinding(keyCode: nil, modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue)
        case .leftHalf: return ShortcutBinding(keyCode: 123, modifiers: controlOption)
        case .rightHalf: return ShortcutBinding(keyCode: 124, modifiers: controlOption)
        case .topHalf: return ShortcutBinding(keyCode: 126, modifiers: controlOption)
        case .bottomHalf: return ShortcutBinding(keyCode: 125, modifiers: controlOption)
        case .topLeft: return ShortcutBinding(keyCode: 32, modifiers: controlOption)
        case .topRight: return ShortcutBinding(keyCode: 34, modifiers: controlOption)
        case .bottomLeft: return ShortcutBinding(keyCode: 38, modifiers: controlOption)
        case .bottomRight: return ShortcutBinding(keyCode: 40, modifiers: controlOption)
        case .maximize: return ShortcutBinding(keyCode: 36, modifiers: controlOption)
        case .maximizeHeight: return ShortcutBinding(keyCode: 126, modifiers: controlOption | CGEventFlags.maskShift.rawValue)
        case .smaller: return ShortcutBinding(keyCode: 27, modifiers: controlOption)
        case .larger: return ShortcutBinding(keyCode: 24, modifiers: controlOption)
        case .center: return ShortcutBinding(keyCode: 8, modifiers: controlOption)
        case .restore: return ShortcutBinding(keyCode: 51, modifiers: controlOption)
        case .nextDisplay: return ShortcutBinding(keyCode: 124, modifiers: controlOption | CGEventFlags.maskCommand.rawValue)
        case .previousDisplay: return ShortcutBinding(keyCode: 123, modifiers: controlOption | CGEventFlags.maskCommand.rawValue)
        case .centerHalf, .almostMaximize: return .unassigned
        }
    }
}

struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt16?
    var modifiers: UInt64
    var disabled = false

    static let unassigned = ShortcutBinding(keyCode: nil, modifiers: 0, disabled: true)
    static let modifierMask = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand]).rawValue
    static func normalized(_ flags: UInt64) -> UInt64 { flags & modifierMask }

    static let keyNames: [UInt16: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",
        18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
        36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",
        64:"F17",65:"Keypad .",67:"Keypad *",69:"Keypad +",71:"Clear",75:"Keypad /",76:"⌤",78:"Keypad −",79:"F18",80:"F19",
        81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"↖",116:"⇞",117:"⌦",118:"F4",119:"↘",120:"F2",121:"⇟",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]

    var modifierLabel: String {
        [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
            .filter { modifiers & $0.0.rawValue != 0 }.map { $0.1 }.joined()
    }

    var displayName: String {
        if disabled { return "단축키 입력" }
        return modifierLabel + (keyCode.flatMap { Self.keyNames[$0] } ?? " + 왼쪽 드래그")
    }

    func validationError(for action: WindowAction) -> String? {
        if disabled { return nil }
        guard modifiers == Self.normalized(modifiers) else { return "지원하지 않는 조합키입니다." }
        if action == .drawRegion {
            return keyCode == nil && modifiers.nonzeroBitCount >= 2 ? nil : "조합키를 두 개 이상 누른 뒤 모두 놓아 주세요."
        }
        guard let keyCode = keyCode, Self.keyNames[keyCode] != nil else { return "다른 키를 선택해 주세요." }
        guard modifiers & CGEventFlags([.maskCommand, .maskControl]).rawValue != 0 else {
            return "Command 또는 Control을 포함해 주세요."
        }
        let commandOnly = modifiers & ~CGEventFlags.maskShift.rawValue == CGEventFlags.maskCommand.rawValue
        let controlOnly = modifiers & ~CGEventFlags.maskShift.rawValue == CGEventFlags.maskControl.rawValue
        if (commandOnly && [12,48,49].contains(keyCode)) || (controlOnly && keyCode == 49) {
            return "macOS에서 사용하는 기본 조합입니다. 다른 조합을 선택해 주세요."
        }
        return nil
    }

    func matches(key: UInt16, flags: UInt64) -> Bool {
        !disabled && keyCode == key && modifiers == Self.normalized(flags)
    }
    func matchesDrag(flags: UInt64) -> Bool {
        !disabled && keyCode == nil && modifiers != 0 && modifiers == Self.normalized(flags)
    }
}
