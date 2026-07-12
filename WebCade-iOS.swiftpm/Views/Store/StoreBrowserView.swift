import SwiftUI

struct StoreBrowserView: View {
    @Environment(\.dismiss) var dismiss
    var library: GameLibrary
    
    @State private var currentTitle: String = String(localized: "Lade itch.io...")
    @State private var currentUrl: String = "https://itch.io/games/html5"
    
    // NEU: Interne States, um die gescrapten Daten zwischenzuspeichern
    @State private var currentDeveloper: String = String(localized: "Unbekannt")
    @State private var currentCoverUrl: String = ""
    
    var isGamePage: Bool {
        return currentUrl.contains(".itch.io/")
    }
    
    var body: some View {
        NavigationStack {
            StoreWebView(
                startUrl: URL(string: "https://itch.io/games/html5")!,
                currentTitle: $currentTitle,
                currentUrl: $currentUrl,
                currentDeveloper: $currentDeveloper,
                currentCoverUrl: $currentCoverUrl
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Hinzufügen")) {
                        // Haptic Feedback beim Hinzufügen
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // NEU: Übergibt jetzt die live extrahierten Daten an die Bibliothek
                        library.addGame(
                            title: currentTitle,
                            developer: currentDeveloper,
                            coverImageUrl: currentCoverUrl.isEmpty ? nil : currentCoverUrl,
                            url: currentUrl
                        )
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(isGamePage ? .blue : .gray)
                    .disabled(!isGamePage)
                }
            }
        }
    }
}
