import SwiftUI

struct PatchNotesView: View {
    @Environment(\.dismiss) private var dismiss
    let patchNotes: [FetchWebDocuments.PatchNote]
    let isLoading: Bool

    var body: some View {
        NavigationView {
            ZStack {
                if isLoading && patchNotes.isEmpty {
                    ProgressView(NSLocalizedString("patchNotes.loading", comment: "Loading..."))
                        .progressViewStyle(.circular)
                } else if patchNotes.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("patchNotes.error.title", comment: "Failed to load patch notes."))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("patchNotes.error.message", comment: "Please try again later."))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(patchNotes) { note in
                            Section {
                                VStack(alignment: .leading, spacing: 16) {
                                    PatchNoteHeader(note: note)
                                    
                                    if !note.features.allSatisfy({ $0.title.isEmpty }) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(note.features, id: \.self) { feature in
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack(alignment: .center, spacing: 6) {
                                                        Image(systemName: "checkmark.circle")
                                                            .font(.subheadline)
                                                            .foregroundColor(.accentColor)
                                                        Text(feature.title)
                                                            .font(.subheadline)
                                                            .foregroundColor(.primary)
                                                            .fixedSize(horizontal: false, vertical: true)
                                                    }
                                                    
                                                    if let description = feature.description, !description.isEmpty {
                                                        let descriptionLines = description.components(separatedBy: "\n")
                                                        ForEach(descriptionLines, id: \.self) { line in
                                                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                                                Text("-")
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)

                                                                Text(line)
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                                    .fixedSize(horizontal: false, vertical: true)
                                                            }
                                                        }
                                                        .padding(.leading, 20)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("patchNotes.title", comment: "Patch Notes"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("appInfo.close", comment: "Close")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

fileprivate struct PatchNoteHeader: View {
    let note: FetchWebDocuments.PatchNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.version)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text(note.date)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 10)
            }
            if !note.title.isEmpty {
                Text(note.title)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 5)
    }
}

#Preview("Loading") {
    PatchNotesView(patchNotes: [], isLoading: true)
}

#Preview("Empty") {
    PatchNotesView(patchNotes: [], isLoading: false)
} 
