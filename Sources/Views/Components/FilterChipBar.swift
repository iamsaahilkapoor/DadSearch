import SwiftUI

public struct FilterChipBar: View {
    @Binding var selectedCategory: SearchCategoryFilter

    public init(selectedCategory: Binding<SearchCategoryFilter>) {
        self._selectedCategory = selectedCategory
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategoryFilter.allCases, id: \.rawValue) { (category: SearchCategoryFilter) in
                    let isSelected = (selectedCategory == category)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundColor(isSelected ? .white : .primary)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
