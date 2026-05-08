import Cocoa
import SwiftUI

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt = Date()

    var timeLabel: String {
        createdAt.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
final class TranscriptHistoryStore: ObservableObject {
    static let shared = TranscriptHistoryStore()

    @Published private(set) var entries: [TranscriptEntry] = []

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries.insert(TranscriptEntry(text: trimmed), at: 0)
        if entries.count > 20 {
            entries.removeLast(entries.count - 20)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

struct TranscriptHistoryView: View {
    @ObservedObject var store: TranscriptHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.title3.weight(.semibold))
                    Text("Recent transcripts are kept for this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear") {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }

            if store.entries.isEmpty {
                ContentUnavailableView("No Transcripts Yet", systemImage: "text.quote", description: Text("Record something and it will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.entries) { entry in
                            TranscriptRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 460, height: 420)
    }
}

private struct TranscriptRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcript")
            }

            Text(entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
