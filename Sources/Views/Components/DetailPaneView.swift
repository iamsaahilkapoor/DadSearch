import SwiftUI
import AppKit

public struct DetailPaneView: View {
    let item: SearchItem?

    public init(item: SearchItem?) {
        self.item = item
    }

    public var body: some View {
        VStack(spacing: 20) {
            if let item = item {
                // Header Thumbnail / Icon
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

                        Image(systemName: item.kind.systemImage)
                            .font(.system(size: 38))
                            .foregroundColor(accentColor(for: item.kind))
                    }

                    Text(item.title)
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)

                    Text(item.kind.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(NSColor.separatorColor).opacity(0.2)))
                }

                Divider()

                // Metadata Rows
                VStack(alignment: .leading, spacing: 14) {
                    MetadataRow(label: "Location", value: item.fileURL?.path ?? "Unknown")
                    MetadataRow(label: "Date", value: item.formattedDate)

                    if let size = item.formattedFileSize {
                        MetadataRow(label: "File Size", value: size)
                    }

                    if let sender = item.authorOrSender {
                        MetadataRow(label: "Sender / Author", value: sender)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Action Buttons
                VStack(spacing: 10) {
                    Button(action: { QuickActionService.shared.open(item: item) }) {
                        Label("Open in Default App", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 8) {
                        Button(action: { QuickActionService.shared.revealInFinder(item: item) }) {
                            Label("Reveal", systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { QuickActionService.shared.toggleQuickLook(for: item) }) {
                            Label("Quick Look", systemImage: "eye")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)

            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Select a file or email to preview")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private func accentColor(for kind: SearchItemKind) -> Color {
        switch kind {
        case .document: return .blue
        case .download: return .green
        case .email: return .indigo
        case .image: return .purple
        case .archive: return .orange
        case .screenshot: return .teal
        case .chatAttachment: return .pink
        case .other: return .gray
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }
}
