// MARK: - Preview Playground
// Preview-only view used for local SwiftUI checks.
import SwiftUI

/// Preview scaffold used to validate styling and interaction basics.
struct ContentView: View {
    /// Temporary counter used to exercise state changes in previews.
    @State private var tapCount = 0

    /// Renders the local preview surface.
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
