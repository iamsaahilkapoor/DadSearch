import SwiftUI

/// Shown whenever DadSearch cannot see part of the Mac. Silent failure was the original bug.
public struct HealthBanner: View {
    @ObservedObject var viewModel: SearchViewModel
    public init(viewModel: SearchViewModel) { self.viewModel = viewModel }

    public var body: some View {
        if let issue = viewModel.healthIssue {
            Button(action: { viewModel.fixHealthIssue() }) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(issue).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.leading)
                    Spacer()
                    Text("Fix").font(.system(size: 12, weight: .bold))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        if let note = viewModel.statusNote {
            Text(note).font(.system(size: 11)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
