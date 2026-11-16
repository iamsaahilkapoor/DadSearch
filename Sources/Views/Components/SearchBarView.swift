import SwiftUI
import AppKit

public struct SearchBarView: View {
    @Binding var text: String
    var isSearching: Bool
    var onCommit: () -> Void

    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, isSearching: Bool = false, onCommit: @escaping () -> Void = {}) {
        self._text = text
        self.isSearching = isSearching
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.secondary)

            TextField("Search downloads, documents, Outlook emails...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .focused($isFocused)
                .onSubmit(onCommit)

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1.5)
                )
        )
        .onAppear {
            isFocused = true
        }
    }
}
