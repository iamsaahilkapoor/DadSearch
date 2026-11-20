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
                            viewModel.handleItemOpened(selected)
                        }
                    }
                )

                FilterChipBar(selectedCategory: $viewModel.selectedCategory)

                CoverageHealthView()

                if viewModel.results.isEmpty && !viewModel.isSearching {
                    VStack(spacing: 14) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 44))
                            .foregroundColor(.orange.opacity(0.8))

                        Text("No matching files, emails, or apps found")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Try searching with general terms or dates (e.g., 'pdf', 'last week')")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if viewModel.rawQuery.isEmpty && !viewModel.todayArrivals.isEmpty && viewModel.selectedCategory == .all {
                    ArrivalRadarTimelineView(
                        items: viewModel.todayArrivals,
                        onSelect: { item in viewModel.selectedItem = item },
                        onOpen: { item in viewModel.handleItemOpened(item) }
                    )
                } else {
                    ScrollViewReader { proxy in
                        List(viewModel.results, selection: $viewModel.selectedItem) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: viewModel.selectedItem == item,
                                onSelect: { viewModel.selectedItem = item },
                                onOpen: { viewModel.handleItemOpened(item) }
                            )
                            .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .id(item.id)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .padding(14)
            .navigationSplitViewColumnWidth(min: 460, ideal: 540, max: 720)

        } detail: {
            DetailPaneView(item: viewModel.selectedItem)
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}
