import SwiftUI
import AppKit

public struct FloatingSearchPanel: View {
    @ObservedObject var viewModel: SearchViewModel
    var onClose: () -> Void

    public init(viewModel: SearchViewModel, onClose: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top input & filter bar
            VStack(spacing: 12) {
                SearchBarView(
                    text: $viewModel.rawQuery,
                    isSearching: viewModel.isSearching,
                    onCommit: {
                        if let selected = viewModel.selectedItem {
                            QuickActionService.shared.open(item: selected)
                            onClose()
                        }
                    }
                )

                FilterChipBar(selectedCategory: $viewModel.selectedCategory)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

            Divider()

            // Results list
            if viewModel.results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("Type anything to find recent downloads, emails, or docs")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(viewModel.results.prefix(30)) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: viewModel.selectedItem == item,
                                onSelect: { viewModel.selectedItem = item },
                                onOpen: {
                                    QuickActionService.shared.open(item: item)
                                    onClose()
                                }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
            }

            Divider()

            // Bottom Keyboard shortcuts hint
            HStack(spacing: 16) {
                ShortcutHint(key: "↵", label: "Open")
                ShortcutHint(key: "Space", label: "Quick Look")
                ShortcutHint(key: "⌘↵", label: "Finder")
                ShortcutHint(key: "Esc", label: "Close")

                Spacer()

                let count = viewModel.results.count
                if count > 0 {
                    Text("\(count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 620)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
    }
}

private struct ShortcutHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(NSColor.separatorColor).opacity(0.3))
                .cornerRadius(4)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
