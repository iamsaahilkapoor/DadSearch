import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject var viewModel: SearchViewModel

    public init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            // Main search list
            VStack(spacing: 12) {
                SearchBarView(
                    text: $viewModel.rawQuery,
                    isSearching: viewModel.isSearching,
                    onCommit: {
                        if let selected = viewModel.selectedItem {
                            QuickActionService.shared.open(item: selected)
                        }
                    }
                )

                FilterChipBar(selectedCategory: $viewModel.selectedCategory)

                if viewModel.results.isEmpty && !viewModel.isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No matching documents or emails found")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Try searching with general terms or dates (e.g., 'pdf', 'last week')")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List(viewModel.results, selection: $viewModel.selectedItem) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: viewModel.selectedItem == item,
                                onSelect: { viewModel.selectedItem = item },
                                onOpen: { QuickActionService.shared.open(item: item) }
                            )
                            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .id(item.id)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .padding(14)
            .navigationSplitViewColumnWidth(min: 440, ideal: 520, max: 700)

        } detail: {
            DetailPaneView(item: viewModel.selectedItem)
        }
        .frame(minWidth: 750, minHeight: 520)
    }
}
