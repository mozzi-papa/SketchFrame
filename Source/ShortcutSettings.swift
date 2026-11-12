import Foundation

final class ShortcutSettings {
    private struct Document: Codable {
        var version = 1
        var overrides: [String: ShortcutBinding] = [:]
    }
    static let storageKey = "shortcutBindings.v1"
    private let defaults: UserDefaults
    private var document = Document()
    private(set) var loadWarning: String?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            if let decoded = try? JSONDecoder().decode(Document.self, from: data), decoded.version == 1 {
                document = decoded
                var used: [ShortcutBinding] = []
                for action in WindowAction.allCases {
                    let binding = self.binding(for: action)
                    if binding.validationError(for: action) != nil || (!binding.disabled && used.contains(binding)) {
                        document.overrides[action.rawValue] = .unassigned
                        loadWarning = "저장된 일부 단축키가 잘못되었거나 중복되어 비활성화했습니다."
                    } else if !binding.disabled { used.append(binding) }
                }
            } else {
                loadWarning = "단축키 설정을 읽지 못해 기본값을 사용합니다."
            }
        }
    }

    func binding(for action: WindowAction) -> ShortcutBinding {
        document.overrides[action.rawValue] ?? action.defaultBinding
    }

    func action(for key: UInt16, flags: UInt64) -> WindowAction? {
        WindowAction.allCases.first { $0 != .drawRegion && binding(for: $0).matches(key: key, flags: flags) }
    }

    @discardableResult
    func set(_ binding: ShortcutBinding, for action: WindowAction) -> String? {
        if let error = binding.validationError(for: action) { return error }
        if !binding.disabled, let duplicate = WindowAction.allCases.first(where: { $0 != action && self.binding(for: $0) == binding }) {
            return "‘\(duplicate.title)’에서 사용 중인 단축키입니다."
        }
        var next = document
        next.overrides[action.rawValue] = binding.disabled ? .unassigned : binding
        guard let data = try? JSONEncoder().encode(next) else { return "설정을 저장하지 못했습니다." }
        defaults.set(data, forKey: Self.storageKey)
        document = next
        loadWarning = nil
        onChange?()
        return nil
    }

    func reset() {
        document = Document()
        defaults.removeObject(forKey: Self.storageKey)
        loadWarning = nil
        onChange?()
    }
}
