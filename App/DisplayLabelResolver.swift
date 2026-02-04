// MARK: - Display Label Resolver
// Centralizes naming + numbering rules for displays.
import Foundation

/// Central place for naming and overlay marker rules.
struct DisplayLabelResolver {
    /// Resolves a friendly, user-facing name for a display.
    static func displayName(
        for display: DisplayInfo,
        settings: DimlySettings,
        externalIndex: Int,
        internalIndex: Int
    ) -> String {
        if let custom = trimmed(settings.displayAliases[display.stableIdentity]), custom.isEmpty == false {
            return custom
        }
        if let name = trimmed(display.name), name.isEmpty == false {
            return name
        }
        if display.isExternal {
            return String(format: String(localized: "DisplayNameExternalFormat"), Int64(externalIndex))
        }
        return internalIndex > 1
            ? String(format: String(localized: "DisplayNameInternalFormat"), Int64(internalIndex))
            : String(localized: "Internal")
    }

    /// Marker string shown in the full-screen overlay (number for most displays, a special tag for a single internal panel).
    static func overlayMarker(
        for display: DisplayInfo,
        externalIndex: Int,
        internalIndex: Int,
        internalCount: Int
    ) -> String {
        if display.isBuiltin && internalCount == 1 {
            return String(localized: "InternalDisplayMarker")
        }
        return String(display.isExternal ? externalIndex : internalIndex)
    }

    /// Trims whitespace from optional strings.
    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
