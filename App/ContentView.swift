// MARK: - Preview Playground
// Lightweight view used only for local preview checks.
import SwiftUI

/// Minimal preview-only view.
struct ContentView: View {
    /// Demo counter for preview interaction.
    @State private var tapCount = 0

    /// Renders a small interactive preview surface.
    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Welcome to Dimly"))
                .font(.largeTitle)
                .bold()
            Text(String(localized: "This SwiftUI scaffold is ready for your ideas."))
                .foregroundStyle(.secondary)
            Button(action: { tapCount += 1 }) {
                Label(String(localized: "Increase Counter"), systemImage: "plus")
            }
            Text(
                String.localizedStringWithFormat(
                    String(localized: "Counter: %lld"),
                    tapCount
                )
            )
                .monospaced()
        }
        .frame(minWidth: 360, minHeight: 240)
        .padding()
    }
}

#Preview {
    ContentView()
}
