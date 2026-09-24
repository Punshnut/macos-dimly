// MARK: - Fluent Interaction
// Reusable interaction effects that keep buttons and tiles responsive without over-animating the UI.
import SwiftUI

enum DimlyMotion {
    static let quickSpring = Animation.spring(response: 0.16, dampingFraction: 0.88)
    /// A slightly bouncier spring for small tap targets (step buttons) that should feel poppy.
    static let poppySpring = Animation.spring(response: 0.22, dampingFraction: 0.62)
    static let standardSpring = Animation.spring(response: 0.24, dampingFraction: 0.84)
    static let panelSpring = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let reorderSpring = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.82, blendDuration: 0.12)
    static let reorderSettleSpring = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.18)
    static let gentleEaseOut = Animation.easeOut(duration: 0.18)
}

/// Compact press animation for plain and custom buttons.
struct FluentPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.94
    var animation: Animation = DimlyMotion.quickSpring

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Applies a quick press-down feedback that respects Reduce Motion.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : animation, value: configuration.isPressed)
    }
}

/// Subtle hover lift for clickable tiles on macOS.
private struct HoverLiftModifier: ViewModifier {
    let enabled: Bool
    let hoverScale: CGFloat
    let shadowOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    /// Adds a subtle hover lift/shadow effect for desktop pointer interaction.
    func body(content: Content) -> some View {
        content
            .scaleEffect((enabled && isHovering && !reduceMotion) ? hoverScale : 1)
            .shadow(
                color: Color.black.opacity((enabled && isHovering) ? shadowOpacity : 0),
                radius: (enabled && isHovering) ? 5 : 0,
                x: 0,
                y: (enabled && isHovering) ? 2 : 0
            )
            .animation(reduceMotion ? nil : DimlyMotion.quickSpring, value: isHovering)
            .onHover { hovering in
                guard enabled else {
                    isHovering = false
                    return
                }
                isHovering = hovering
            }
    }
}

extension View {
    /// Opts a view into Dimly's reusable hover-lift treatment.
    func dimlyHoverLift(enabled: Bool = true, hoverScale: CGFloat = 1.015, shadowOpacity: Double = 0.12) -> some View {
        modifier(HoverLiftModifier(enabled: enabled, hoverScale: hoverScale, shadowOpacity: shadowOpacity))
    }
}

/// A single, app-owned surface treatment for chrome elements (icon buttons, pills, cards).
///
/// On macOS 26+ this uses the system Liquid Glass effect (`.glassEffect`), which the OS
/// renders and animates natively and keeps power-efficient. On older systems it falls back
/// to Dimly's existing tinted, translucent chip look. Centralizing this in one place means
/// surfaces never again silently depend on a system control style (e.g. `.bordered`) that
/// can change appearance across macOS releases.
struct DimlyGlassSurface: ViewModifier {
    var shape: AnyShape
    var tint: Color
    var fillOpacity: Double
    var strokeOpacity: Double

    init(cornerRadius: CGFloat, tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32) {
        self.shape = AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        self.tint = tint
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
    }

    init(circle tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32) {
        self.shape = AnyShape(Circle())
        self.tint = tint
        self.fillOpacity = fillOpacity
        self.strokeOpacity = strokeOpacity
    }

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(fillOpacity * 1.6)).interactive(), in: shape)
        } else {
            content
                .background(shape.fill(tint.opacity(fillOpacity)))
                .overlay(shape.stroke(tint.opacity(strokeOpacity), lineWidth: 0.75))
        }
    }
}

extension View {
    /// Rounded-rectangle glass/chip surface — see `DimlyGlassSurface`.
    func dimlyGlassSurface(cornerRadius: CGFloat, tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32) -> some View {
        modifier(DimlyGlassSurface(cornerRadius: cornerRadius, tint: tint, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }

    /// Circular glass/chip surface — see `DimlyGlassSurface`.
    func dimlyGlassCircle(tint: Color = .primary, fillOpacity: Double = 0.1, strokeOpacity: Double = 0.32) -> some View {
        modifier(DimlyGlassSurface(circle: tint, fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
    }
}
