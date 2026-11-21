import SwiftUI
import AppKit

public struct DetailPaneView: View {
    let item: SearchItem?
    @State private var thumbnail: NSImage? = nil

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
                            .frame(width: 100, height: 100)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                        if let thumb = thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 90, height: 90)
                                .cornerRadius(12)
                        } else {
                            Image(systemName: item.kind.systemImage)
                                .font(.system(size: 44))
                                .foregroundColor(accentColor(for: item.kind))
                        }
                    }

                    Text(item.title)
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)

                    Text(item.kind.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(NSColor.separatorColor).opacity(0.25)))
                }
                .task(id: item.id) {
                    loadThumbnail(for: item)
                }

                Divider()

                // Metadata Rows
                VStack(alignment: .leading, spacing: 14) {
                    MetadataRow(label: "Location", value: item.fileURL?.path ?? item.subtitle)
                    MetadataRow(label: "Date", value: item.formattedDate)

                    if let size = item.formattedFileSize {
                        MetadataRow(label: "File Size", value: size)
                    }

                    if let sender = item.authorOrSender {
                        MetadataRow(label: "Source / Author", value: sender)
                    }

                    if item.score > 0 {
                        MetadataRow(label: "Match Confidence", value: "\(Int(item.score))%")
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Action Buttons
                VStack(spacing: 10) {
                    Button(action: { QuickActionService.shared.open(item: item) }) {
                        Label(item.kind == .application ? "Launch Application" : "Open in Default App", systemImage: item.kind == .application ? "play.fill" : "arrow.up.forward.app")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)

                    if item.fileURL != nil {
                        HStack(spacing: 8) {
                            Button(action: { QuickActionService.shared.revealInFinder(item: item) }) {
                                Label("Reveal", systemImage: "folder")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)

                            Button(action: { QuickActionService.shared.toggleQuickLook(for: item) }) {
                                Label("Quick Look", systemImage: "eye")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)

            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("Select a file or result to preview")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 290)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    private func loadThumbnail(for item: SearchItem) {
        guard let url = item.fileURL else {
            self.thumbnail = nil
            return
        }
        ThumbnailCacheService.shared.fetchThumbnail(for: url, size: CGSize(width: 160, height: 160)) { @MainActor img in
            self.thumbnail = img
        }
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
        case .application: return .cyan
        case .contact: return .orange
        case .calendarEvent: return .red
        case .note: return .yellow
        case .folder: return .secondary
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
