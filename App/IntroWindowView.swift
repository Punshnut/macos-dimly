// MARK: - Intro Window
// Simple first-launch welcome window pointing to the menu bar.
import SwiftUI
import AppKit

struct IntroWindowView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.thinMaterial)
                        Image(systemName: "display")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Welcome to Dimly"))
                            .font(.title2.bold())
                        Text(String(localized: "Your displays, one click away."))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "Dimly lives in the menu bar."))
                        .font(.headline)
                    Text(String(localized: "Look at the top-right of your screen for the display icon."))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Button(String(localized: "Got it")) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            VStack(alignment: .trailing, spacing: 6) {
                Text(String(localized: "Menu bar"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}

#Preview {
    IntroWindowView(onDismiss: {})
        .frame(width: 420, height: 260)
}
