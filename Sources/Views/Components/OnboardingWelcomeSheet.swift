import SwiftUI

public struct OnboardingWelcomeSheet: View {
    var onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 24) {
            // App Icon & Title
            VStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Welcome to DadSearch")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("Universal, frustration-free search for your Mac")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 16)

            // 3 Key Highlights
            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(
                    icon: "keyboard",
                    color: .blue,
                    title: "Open Anywhere: ⌥ Space",
                    description: "Press Option + Space from any app to bring up DadSearch instantly."
                )

                FeatureRow(
                    icon: "text.bubble",
                    color: .green,
                    title: "Speak or Type Naturally",
                    description: "Search 'pdf from last week', 'screenshot receipt', or 'whatsapp invoice'."
                )

                FeatureRow(
                    icon: "eye",
                    color: .orange,
                    title: "Quick Look: Spacebar",
                    description: "Select any document or image and tap Space to see a full preview without opening."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Dismiss Button
            Button(action: onDismiss) {
                Text("Got It, Let's Search!")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
