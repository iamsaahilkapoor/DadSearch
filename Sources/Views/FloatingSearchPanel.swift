import SwiftUI
import AppKit

public struct FloatingSearchPanel: View {
    @ObservedObject var viewModel: SearchViewModel
    var onClose: () -> Void

    @AppStorage("com.saahil.DadSearch.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showingOnboarding: Bool = false

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

            // Results list or Empathetic Empty State
            if viewModel.results.isEmpty && !viewModel.isSearching {
                VStack(spacing: 14) {
                    if viewModel.rawQuery.isEmpty {
                        // Empty query state with tips & recent searches
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 38))
                            .foregroundColor(.secondary.opacity(0.7))

                        Text("Type anything to find downloads, emails, or apps")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Try searching: 'pdf from last week', 'screenshot', or an app name")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        if !viewModel.recentQueries.isEmpty {
                            VStack(spacing: 6) {
                                Text("Recent searches:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    ForEach(viewModel.recentQueries.prefix(3), id: \.self) { query in
                                        Button(action: { viewModel.rawQuery = query }) {
                                            Text(query)
                                                .font(.system(size: 11, weight: .medium))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color(NSColor.separatorColor).opacity(0.2))
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        // Empathetic "No Results" state
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange.opacity(0.8))

                        Text("No matching files found for \"\(viewModel.rawQuery)\"")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Tip: Check your spelling or try searching by category (like 'PDF & Docs')")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 44)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(viewModel.results.prefix(40)) { item in
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
                .frame(maxHeight: 430)
            }

            Divider()

            // Bottom Keyboard shortcuts hint & Status
            HStack(spacing: 16) {
                ShortcutHint(key: "↵", label: "Open")
                ShortcutHint(key: "Space", label: "Quick Look")
                ShortcutHint(key: "⌘↵", label: "Finder")
                ShortcutHint(key: "Esc", label: "Close")

                Spacer()

                Button(action: { showingOnboarding = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show DadSearch Guide")

                let count = viewModel.results.count
                if count > 0 {
                    Text("\(count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 640)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, x: 0, y: 14)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingWelcomeSheet(onDismiss: {
                hasCompletedOnboarding = true
                showingOnboarding = false
            })
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
        }
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
                .background(Color(NSColor.separatorColor).opacity(0.35))
                .cornerRadius(4)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
