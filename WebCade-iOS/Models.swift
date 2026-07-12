import Foundation
import SwiftUI

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

// MARK: - Bibliothek (@Observable, ersetzt ObservableObject)

@Observable
class GameLibrary {
    var games: [WebGame] = [] {
        didSet {
            scheduleSave()
        }
    }
    private var saveTimer: Timer?
    
    init() {
        loadGames()
    }

    // MARK: - Persistenz (JSON-Datei statt UserDefaults)

    private var libraryFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library.json")
    }
    
    /// Debounced Save: Sammelt schnelle Änderungen und schreibt erst 0.5s nach der letzten Mutation
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.saveGames()
        }
    }

    // Nimmt Entwickler und Cover-URL direkt beim Scrapen entgegen
    func addGame(title: String, developer: String, coverImageUrl: String?, url: String) {
        let newGame = WebGame(
            title: title.isEmpty ? String(localized: "Neues Spiel") : title,
            developer: developer.isEmpty ? String(localized: "Unbekannt") : developer,
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
                AppLogger.info("Spielordner gelöscht: \(id.uuidString)")
            } catch {
                AppLogger.error("Spielordner konnte nicht gelöscht werden", error: error)
            }
        }

        games.removeAll { $0.id == id }
    }
    
    /// Mutiert ein Spiel anhand seiner ID und speichert automatisch
    func updateGame(withId id: UUID, _ mutation: (inout WebGame) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        mutation(&games[index])
    }

    private func saveGames() {
        do {
            let data = try JSONEncoder().encode(games)
            try data.write(to: libraryFileURL, options: .atomic)
        } catch {
            AppLogger.error("Bibliothek konnte nicht gespeichert werden", error: error)
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
            AppLogger.warning("Bibliothek konnte nicht geladen werden (evtl. altes Format)", error: error)
            self.games = []
        }
    }
}
