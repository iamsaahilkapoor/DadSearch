import SwiftUI
import AppKit

public struct SearchResultRow: View {
    let item: SearchItem
    let isSelected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void

    @State private var isHovered: Bool = false

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
            // Kind icon badge
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badgeColor)
            }

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
                    Button(action: { QuickActionService.shared.open(item: item) }) {
                        Label("Open", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Open in default app (Return)")

                    Button(action: { QuickActionService.shared.revealInFinder(item: item) }) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .padding(6)
                            .background(Color(NSColor.separatorColor).opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder (⌘ + Enter)")

                    Button(action: { QuickActionService.shared.copyPath(item: item) }) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .padding(6)
                            .background(Color(NSColor.separatorColor).opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Path")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
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
        case .other: return .gray
        }
    }
}
