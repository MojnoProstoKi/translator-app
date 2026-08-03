import SwiftUI
import TranslationEngine

/// Lists past translation sessions and lets the user delete any one independently (FR-016).
public struct SessionHistoryView: View {
    @ObservedObject private var viewModel: SessionHistoryViewModel

    public init(viewModel: SessionHistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text("История сессий")
                .font(.headline)
                .padding([.top, .horizontal])

            if viewModel.summaries.isEmpty {
                Text("Пока нет сохранённых сессий.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(viewModel.summaries) { summary in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title)
                                Text(
                                    "\(summary.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(sourcesLabel(summary.sourceTypes))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Single tap = 1 action, well within SC-006's 2-action budget.
                            Button(role: .destructive) {
                                viewModel.delete(sessionId: summary.sessionId)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text(viewModel.sessionsDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Изменить папку…") {
                    viewModel.changeDirectory()
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 360, minHeight: 240)
        .onAppear { viewModel.refresh() }
    }

    private func sourcesLabel(_ sources: Set<AudioSourceType>) -> String {
        sources.map { $0 == .microphone ? "Микрофон" : "Системный звук" }
            .sorted()
            .joined(separator: " + ")
    }
}
