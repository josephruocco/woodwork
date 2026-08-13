import SwiftUI
import AppKit

@main
struct ScannerApp: App {
    var body: some Scene {
        Window("WoodWork Scanner", id: "main") {
            ScannerView()
        }
        .windowResizability(.contentSize)
    }
}

struct ScannerView: View {
    @StateObject private var scanner = LibraryScanner()

    var body: some View {
        VStack(spacing: 16) {
            ShelfView(books: preview)
                .frame(height: 236)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(scanner.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Scan Library") { Task { await scanner.scan() } }
                    .keyboardShortcut(.defaultAction)

                if scanner.needsFolderPick {
                    Button("Choose BKLibrary Folder…", action: pickFolder)
                }

                Spacer()

                if scanner.busy { ProgressView().controlSize(.small) }

                Button("Save books.json…", action: save)
                    .disabled(scanner.books.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Show real books once scanned, samples before that, so the window is never
    /// an empty box.
    private var preview: [Book] {
        var rng = SeededRNG(seed: 7)
        return scanner.books.isEmpty ? .samples : scanner.books.shuffled(using: &rng)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Select the BKLibrary folder (or its .sqlite file) inside the Apple Books container."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.apple.iBooksX/Data/Documents")
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        let db = picked.pathExtension == "sqlite" ? picked
            : (try? FileManager.default.contentsOfDirectory(at: picked, includingPropertiesForKeys: nil))?
                .first { $0.pathExtension == "sqlite" }
        guard let db else { return }
        Task { await scanner.scan(booksDBOverride: db) }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "books.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try scanner.export(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            scanner.status = "Save failed: \(error.localizedDescription)"
        }
    }
}
