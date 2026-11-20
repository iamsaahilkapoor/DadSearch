import SwiftUI

public struct CoverageHealthView: View {
    @ObservedObject var healthService = CoverageHealthService.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            if healthService.hasFullDiskAccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("\(healthService.indexedFileCount) items indexed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("Full Disk Access needed for Mail & Chat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Button(action: {
                        healthService.openPrivacySettings()
                    }) {
                        Text("Fix")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .onAppear {
            healthService.checkHealth()
        }
    }
}
