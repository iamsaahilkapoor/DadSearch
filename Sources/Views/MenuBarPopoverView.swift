import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: SearchViewModel

    public init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 10) {
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
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(viewModel.rawQuery.isEmpty ? "No recent items found" : "No results for \"\(viewModel.rawQuery)\"")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(height: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.results.prefix(25)) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: viewModel.selectedItem == item,
                                onSelect: { viewModel.selectedItem = item },
                                onOpen: { QuickActionService.shared.open(item: item) }
                            )
                        }
                    }
                }
                .frame(height: 390)
            }
        }
        .padding(12)
        .frame(width: 480)
    }
}
