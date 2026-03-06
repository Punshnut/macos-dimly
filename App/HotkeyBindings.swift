// MARK: - Hotkey Bindings
// Defines user-configurable hotkey targets and actions.
import Foundation

/// User-facing actions that can be bound to a hotkey.
enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleWindow
    case toggleBlackout
    case toggleSleepWake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleWindow:
            return String(localized: "Toggle Window")
        case .toggleBlackout:
            return String(localized: "Toggle Blackout")
        case .toggleSleepWake:
            return String(localized: "Toggle Sleep/Wake")
        }
    }

    var usesTarget: Bool {
        switch self {
        case .toggleWindow:
            return false
        case .toggleBlackout, .toggleSleepWake:
            return true
        }
    }
}

/// Target selection for a hotkey action.
enum HotkeyTarget: Hashable, Codable {
    case allExternalDisplays
    case display(id: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case displayID
    }

    private enum Kind: String, Codable {
        case allExternalDisplays
        case display
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .allExternalDisplays:
            self = .allExternalDisplays
        case .display:
            let displayID = try container.decode(String.self, forKey: .displayID)
            self = .display(id: displayID)
        }
    }

    /// Encodes the target type (`allExternalDisplays` or specific display ID).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allExternalDisplays:
            try container.encode(Kind.allExternalDisplays, forKey: .kind)
        case .display(let id):
            try container.encode(Kind.display, forKey: .kind)
            try container.encode(id, forKey: .displayID)
        }
    }
}

/// Persisted hotkey binding (action + target + optional descriptor).
struct HotkeyBinding: Identifiable, Codable, Equatable {
    let id: UUID
    var action: HotkeyAction
    var target: HotkeyTarget
    var descriptor: HotkeyDescriptor?

    init(id: UUID = UUID(), action: HotkeyAction, target: HotkeyTarget, descriptor: HotkeyDescriptor?) {
        self.id = id
        self.action = action
        self.target = target
        self.descriptor = descriptor
    }
}
