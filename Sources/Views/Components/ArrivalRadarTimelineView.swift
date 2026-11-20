import SwiftUI

public struct ArrivalRadarTimelineView: View {
    let items: [SearchItem]
    var onSelect: (SearchItem) -> Void
    var onOpen: (SearchItem) -> Void

    public init(
        items: [SearchItem],
        onSelect: @escaping (SearchItem) -> Void,
        onOpen: @escaping (SearchItem) -> Void
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accentColor)

                Text("Arrival Radar — Landed Today")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(items.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No new files landed yet today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Downloads from Chrome, WhatsApp, and Mail will appear here automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            SearchResultRow(
                                item: item,
                                isSelected: false,
                                onSelect: { onSelect(item) },
                                onOpen: { onOpen(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}
