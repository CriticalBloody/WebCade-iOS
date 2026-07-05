import Foundation
import SwiftUI
import Combine

// MARK: - Datenmodelle & Bibliothek

struct WebGame: Identifiable, Codable {
    var id = UUID()
    let title: String
    var developer: String
    var colorName: String
    var localPath: String?
    var isDownloaded: Bool = false
    let sourceUrl: String
    var iframeUrl: String?
    var coverImageUrl: String?
    
    // NEU: Update-Tracking Metadaten
    var gameVersion: String?           // Für die version.json (Unity etc.)
    var lastModifiedHeader: String?    // Für den itch.io HTTP-Header
    
    var coverColor: Color {
        switch colorName {
        case "purple": return .purple
        case "orange": return .orange
        case "green": return .green
        case "pink": return .pink
        default: return .blue
        }
    }
}

class GameLibrary: ObservableObject {
    @Published var games: [WebGame] = [] {
        didSet { saveGames() }
    }
    
    init() { loadGames() }
    
    // Nimmt Entwickler und Cover-URL direkt beim Scrapen entgegen
    func addGame(title: String, developer: String, coverImageUrl: String?, url: String) {
        let colors = ["blue", "purple", "orange", "green", "pink"]
        let newGame = WebGame(
            title: title.isEmpty ? "Neues Spiel" : title,
            developer: developer.isEmpty ? "Unbekannt" : developer,
            colorName: colors.randomElement() ?? "blue",
            sourceUrl: url,
            coverImageUrl: coverImageUrl
        )
        games.append(newGame)
    }
    
    func deleteGame(withId id: UUID) {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
        if let encoded = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(encoded, forKey: "savedWebGames")
        }
    }
    
    private func loadGames() {
        if let savedData = UserDefaults.standard.data(forKey: "savedWebGames"),
           let decoded = try? JSONDecoder().decode([WebGame].self, from: savedData) {
            self.games = decoded
        } else {
            // Die App startet mit einer sauberen, leeren Bibliothek
            self.games = []
        }
    }
}
