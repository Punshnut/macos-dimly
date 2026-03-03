// MARK: - Fluent Interaction
// Reusable interaction effects that keep clicks and hover states responsive without heavy motion.
import SwiftUI

enum DimlyMotion {
    static let quickSpring = Animation.spring(response: 0.16, dampingFraction: 0.88)
    static let standardSpring = Animation.spring(response: 0.24, dampingFraction: 0.84)
    static let gentleEaseOut = Animation.easeOut(duration: 0.18)
}

/// Lightweight press animation for plain/custom buttons.
struct FluentPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.94

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : DimlyMotion.quickSpring, value: configuration.isPressed)
    }
}

/// Subtle hover lift for clickable tiles on macOS.
private struct HoverLiftModifier: ViewModifier {
    let enabled: Bool
    let hoverScale: CGFloat
    let shadowOpacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

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
    func dimlyHoverLift(enabled: Bool = true, hoverScale: CGFloat = 1.015, shadowOpacity: Double = 0.12) -> some View {
        modifier(HoverLiftModifier(enabled: enabled, hoverScale: hoverScale, shadowOpacity: shadowOpacity))
    }
}
