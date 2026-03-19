// MARK: - Display Label Resolver
// Shared naming and marker rules used by display-label overlays.
import Foundation

/// Resolves user-facing titles and markers for display overlays.
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

    /// Resolves the marker shown in the full-screen overlay for a display.
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

    /// Trims surrounding whitespace from optional strings before label selection.
    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
