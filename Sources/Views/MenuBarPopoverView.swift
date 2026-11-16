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

            if viewModel.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No recent files found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(height: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.results.prefix(20)) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: viewModel.selectedItem == item,
                                onSelect: { viewModel.selectedItem = item },
                                onOpen: { QuickActionService.shared.open(item: item) }
                            )
                        }
                    }
                }
                .frame(height: 380)
            }
        }
        .padding(12)
        .frame(width: 460)
    }
}
