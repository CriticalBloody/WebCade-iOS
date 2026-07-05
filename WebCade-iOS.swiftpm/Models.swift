import Foundation
import SwiftUI
import Combine

// MARK: - GameColor Enum

enum GameColor: String, Codable, CaseIterable {
    case blue, purple, orange, green, pink

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .green:  return .green
        case .pink:   return .pink
        }
    }
}

// MARK: - Datenmodell

struct WebGame: Identifiable, Codable {
    var id = UUID()
    let title: String
    var developer: String
    var colorCode: GameColor
    var localPath: String?
    var isDownloaded: Bool = false
    let sourceUrl: String
    var iframeUrl: String?
    var coverImageUrl: String?

    // Update-Tracking Metadaten
    var gameVersion: String?        // Für die version.json (Unity etc.)
    var lastModifiedHeader: String? // Für den itch.io HTTP-Header

    var coverColor: Color { colorCode.color }
}

class GameLibrary: ObservableObject {
    @Published var games: [WebGame] = [] {
        didSet { saveGames() }
    }
    
    init() { loadGames() }

    // MARK: - Persistenz (JSON-Datei statt UserDefaults)

    private var libraryFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library.json")
    }

    // Nimmt Entwickler und Cover-URL direkt beim Scrapen entgegen
    func addGame(title: String, developer: String, coverImageUrl: String?, url: String) {
        let newGame = WebGame(
            title: title.isEmpty ? "Neues Spiel" : title,
            developer: developer.isEmpty ? "Unbekannt" : developer,
            colorCode: GameColor.allCases.randomElement() ?? .blue,
            sourceUrl: url,
            coverImageUrl: coverImageUrl
        )
        games.append(newGame)
    }

    func deleteGame(withId id: UUID) {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let gameFolder = docsPath.appendingPathComponent(id.uuidString)

        if FileManager.default.fileExists(atPath: gameFolder.path) {
            do {
                try FileManager.default.removeItem(at: gameFolder)
                print("🗑️ Festplatte: Ordner erfolgreich gelöscht.")
            } catch {
                print("❌ Fehler beim Löschen des Ordners: \(error)")
            }
        }

        games.removeAll { $0.id == id }
    }

    private func saveGames() {
        do {
            let data = try JSONEncoder().encode(games)
            try data.write(to: libraryFileURL, options: .atomic)
        } catch {
            print("❌ Bibliothek konnte nicht gespeichert werden: \(error)")
        }
    }

    private func loadGames() {
        guard FileManager.default.fileExists(atPath: libraryFileURL.path) else {
            self.games = []
            return
        }
        do {
            let data = try Data(contentsOf: libraryFileURL)
            self.games = try JSONDecoder().decode([WebGame].self, from: data)
        } catch {
            print("⚠️ Bibliothek konnte nicht geladen werden (evtl. altes Format): \(error)")
            self.games = []
        }
    }
}
