// MARK: - Dimly Glass
// Central design layer: Liquid Glass on macOS 26+, translucent material on older systems,
// and opaque surfaces whenever the user enables "Reduce Transparency".
// Glass "Clear/Tinted" (System Settings > Appearance) is resolved by the system inside `.glassEffect(.regular)`,
// so we deliberately do not override it with our own tints on neutral surfaces.
import SwiftUI

/// Shared corner radii so nested surfaces stay concentric.
enum DimlyRadius {
    static let card: CGFloat = 18
    static let tile: CGFloat = 14
    static let control: CGFloat = 10
    static let chip: CGFloat = 8
}

/// A single, app-owned surface treatment for chrome elements (icon buttons, pills, cards).
///
/// - macOS 26+ (transparency allowed): system Liquid Glass.
/// - Reduce Transparency enabled: opaque control background with a hairline.
/// - macOS 14-25: Dimly's tinted translucent chip look.
struct DimlyGlassSurface: ViewModifier {
    var shape: AnyShape
    var tint: Color
    var fillOpacity: Double
    var strokeOpacity: Double
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(cornerRadius: CGFloat, tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32, interactive: Bool = true) {
        self.shape = AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        self.tint = tint
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
        self.interactive = interactive
    }

    init(circle tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32, interactive: Bool = true) {
        self.shape = AnyShape(Circle())
        self.tint = tint
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
        self.interactive = interactive
    }

    private var isNeutralTint: Bool { tint == .primary }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                .background(shape.fill(tint.opacity(fillOpacity)))
                .overlay(shape.stroke(tint.opacity(max(strokeOpacity, 0.2)), lineWidth: 0.75))
        } else if #available(macOS 26, *) {
            let glass: Glass = isNeutralTint ? .regular : .regular.tint(tint.opacity(fillOpacity * 1.6))
            content
                .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        } else {
            content
                .background(shape.fill(tint.opacity(fillOpacity)))
                .overlay(shape.stroke(tint.opacity(strokeOpacity), lineWidth: 0.75))
        }
    }
}

/// Larger, non-interactive container surface (cards, panels).
private struct DimlyCardSurface: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.75))
        } else if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                    }
                }
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(
                    shape.strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10),
                        lineWidth: 0.75
                    )
                )
        }
    }
}

/// Inner plate (header card, display rows, tiles) that replaces the old fill + hard 1pt stroke combination.
/// Liquid Glass on macOS 26+, translucent fill and hairline before, opaque when transparency is reduced.
private struct DimlyPlate<S: InsettableShape>: ViewModifier {
    var shape: S
    var strong: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.75))
        } else if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                    }
                }
        } else {
            content
                .background(shape.fill(strong
                    ? (dark ? Color.white.opacity(0.13) : Color.white.opacity(0.62))
                    : (dark ? Color.white.opacity(0.1) : Color.white.opacity(0.5))))
                .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.09), lineWidth: 0.75))
        }
    }
}

/// Window background for the menu bar popover. macOS 26+ windows already supply system glass
/// and rounding, so adding our own fill there produced a second, square frame.
private struct DimlyPanelBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content.background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
        }
    }
}

private struct DimlyButtonStyleModifier: ViewModifier {
    var prominent: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    /// Rounded-rectangle glass/chip surface - see `DimlyGlassSurface`.
    func dimlyGlassSurface(cornerRadius: CGFloat, tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32, interactive: Bool = true) -> some View {
        modifier(DimlyGlassSurface(cornerRadius: cornerRadius, tint: tint, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity, interactive: interactive))
    }

    /// Circular glass/chip surface - see `DimlyGlassSurface`.
    func dimlyGlassCircle(tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32, interactive: Bool = true) -> some View {
        modifier(DimlyGlassSurface(circle: tint, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity, interactive: interactive))
    }

    /// Non-interactive card surface (Liquid Glass / material / opaque depending on system settings).
    func dimlyCard(cornerRadius: CGFloat = DimlyRadius.card) -> some View {
        modifier(DimlyCardSurface(cornerRadius: cornerRadius))
    }

    /// Inner plate for rows/tiles/cards inside the popover - see `DimlyPlate`.
    func dimlyPlate<S: InsettableShape>(_ shape: S, strong: Bool = false) -> some View {
        modifier(DimlyPlate(shape: shape, strong: strong))
    }

    /// Background for the menu bar popover window.
    func dimlyPanelBackground() -> some View {
        modifier(DimlyPanelBackground())
    }

    /// `.glass`/`.glassProminent` on macOS 26+, `.bordered`/`.borderedProminent` before.
    func dimlyButtonStyle(prominent: Bool = false) -> some View {
        modifier(DimlyButtonStyleModifier(prominent: prominent))
    }
}
