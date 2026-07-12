import Foundation
import SwiftUI

struct ContentView: View {
    @State private var serverManager = LocalServerManager.shared
    @State private var library = GameLibrary()
    
    @State private var showingAddSheet = false
    @State private var showingDeleteConfirm = false
    @State private var gameToDelete: WebGame? = nil
    
    let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty {
                    EmptyLibraryView(showingAddSheet: $showingAddSheet)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 30) {
                            ForEach(library.games) { game in
                                NavigationLink(value: game.id) {
                                    GameCardView(game: game)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        gameToDelete = game
                                        showingDeleteConfirm = true
                                    }) {
                                        Label(String(localized: "Spiel löschen"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        // Haptic Feedback beim Pull-to-Refresh
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
            }
            .navigationTitle(String(localized: "Meine Web-Games"))
            .navigationDestination(for: UUID.self) { gameId in
                if let index = library.games.firstIndex(where: { $0.id == gameId }) {
                    GamePlayerView(game: $library.games[index])
                }
            }
            .toolbar {
                Button(action: {
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                StoreBrowserView(library: library)
            }
            .confirmationDialog(
                String(localized: "\(gameToDelete?.title ?? "Spiel") wirklich löschen?"),
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Löschen"), role: .destructive) {
                    if let game = gameToDelete {
                        // Haptic Feedback beim Löschen
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        library.deleteGame(withId: game.id)
                    }
                    gameToDelete = nil
                }
                Button(String(localized: "Abbrechen"), role: .cancel) {
                    gameToDelete = nil
                }
            } message: {
                Text(String(localized: "Alle heruntergeladenen Daten und Spielstände werden unwiderruflich gelöscht."))
            }
        }
    }
}
