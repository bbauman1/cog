import SwiftUI

struct WikiHubView: View {
    var body: some View {
        List {
            Section("Resources") {
                NavigationLink {
                    KnowledgeListView()
                } label: {
                    WikiResourceRow(
                        title: "Knowledge Notes",
                        subtitle: "Reusable guidance Devin can apply across sessions",
                        systemImage: "note.text"
                    )
                }

                NavigationLink {
                    PlaybookListView()
                } label: {
                    WikiResourceRow(
                        title: "Playbooks",
                        subtitle: "Instruction sets for repeatable Devin workflows",
                        systemImage: "book.pages"
                    )
                }
            }
        }
        .navigationTitle("Wiki")
    }
}

private struct WikiResourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
