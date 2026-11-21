import SwiftUI
import AppKit

public struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void

    @State private var isHovered: Bool = false
    @State private var thumbnail: NSImage? = nil

    public init(
        item: SearchItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void = {},
        onOpen: @escaping () -> Void = {}
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Kind icon badge or QL Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                } else {
                    Circle()
                        .fill(badgeColor.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(badgeColor)
                }
            }
            .frame(width: 44, height: 44)

            // Title, Subtitle, and Metadata
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(item.formattedDate)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let sizeStr = item.formattedFileSize {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(sizeStr)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Quick Actions (always visible on hover or selection)
            if isHovered || isSelected {
                HStack(spacing: 6) {
                    Button(action: {
                        QuickActionService.shared.open(item: item)
                    }) {
                        Label(actionButtonLabel, systemImage: actionButtonIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Open (Return)")

                    if item.fileURL != nil {
                        Button(action: { QuickActionService.shared.revealInFinder(item: item) }) {
                            Image(systemName: "folder")
                                .font(.system(size: 13, weight: .medium))
                                .padding(7)
                                .background(Color(NSColor.separatorColor).opacity(0.2))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder (⌘ + Enter)")

                        Button(action: { QuickActionService.shared.toggleQuickLook(for: item) }) {
                            Image(systemName: "eye")
                                .font(.system(size: 13, weight: .medium))
                                .padding(7)
                                .background(Color(NSColor.separatorColor).opacity(0.2))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Quick Look Preview (Space)")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                onOpen()
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            loadThumbnail()
        }
        // Accessibility (HIG Lens 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.displayName): \(item.title)")
        .accessibilityValue("\(item.subtitle), \(item.formattedDate)")
        .accessibilityHint("Double click or press Return to open. Press Space to preview.")
    }

    private func loadThumbnail() {
        guard let url = item.fileURL else { return }
        ThumbnailCacheService.shared.fetchThumbnail(for: url, size: CGSize(width: 80, height: 80)) { @MainActor img in
            self.thumbnail = img
        }
    }

    private var actionButtonLabel: String {
        switch item.kind {
        case .application: return "Launch"
        case .contact: return "View"
        case .calendarEvent: return "Open"
        default: return "Open"
        }
    }

    private var actionButtonIcon: String {
        switch item.kind {
        case .application: return "play.fill"
        case .contact: return "person.fill"
        default: return "arrow.up.forward.app"
        }
    }

    private var badgeColor: Color {
        switch item.kind {
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
