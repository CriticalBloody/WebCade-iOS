import SwiftUI
import WebKit

// MARK: - UI Ansichten

struct ContentView: View {
    @StateObject private var serverManager = LocalServerManager.shared
    @StateObject private var library = GameLibrary()
    
    @State private var showingAddSheet = false
    
    let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach($library.games) { $game in
                        NavigationLink(destination: GamePlayerView(game: $game)) {
                            GameCardView(game: game)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(action: {
                                library.deleteGame(withId: game.id)
                            }) {
                                Label("Spiel löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Meine Web-Games")
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
        }
    }
}

struct GameCardView: View {
    let game: WebGame
    
    var body: some View {
        VStack(alignment: .leading) {
            
            // LÖSUNG: Das farbige Rechteck gibt die strenge Breite des Grids vor.
            // Das Bild wird als Overlay exakt in diese Form gepresst.
            RoundedRectangle(cornerRadius: 16)
                .fill(game.coverColor.gradient)
                .overlay {
                    if let urlString = game.coverImageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                    }
                }
                .frame(height: 140) // Feste Kachelhöhe
                .clipShape(RoundedRectangle(cornerRadius: 16)) // Schneidet ab, was übersteht
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            Text(game.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 4)
                .padding(.horizontal, 4)
            
            Text(game.developer)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
    }
}

struct GamePlayerView: View {
    @Binding var game: WebGame
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var downloader = GameDownloader()
    @State private var discoveredIframeUrl: String? = nil
    
    // NEU: Update-Status Variablen
    @State private var isCheckingForUpdates = false
    @State private var showGame = false
    
    var currentLocalPath: String {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsPath.appendingPathComponent(game.id.uuidString).path
    }
    
    var body: some View {
        Group {
            if showGame {
                // Das Spiel startet ganz normal vom lokalen Server
                GameWebView(url: URL(string: "http://localhost:8080/index.html")!, discoveredIframeUrl: .constant(nil))
                    .onAppear {
                        LocalServerManager.shared.startServer(for: currentLocalPath, iframeUrlString: game.iframeUrl)
                    }
            } else if game.isDownloaded {
                // NEU: Update-Screen (Ladebildschirm)
                ZStack {
                    // LÖSUNG: Wir füllen ein echtes Rechteck mit dem Gradienten
                    Rectangle()
                        .fill(game.coverColor.gradient)
                        .ignoresSafeArea()
                                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text(isCheckingForUpdates ? "Prüfe auf Updates..." : downloader.statusText)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .onAppear {
                    runUpdateCheckFlow() // Startet den Check automatisch!
                }
            } else {
                // Noch nie geladen: Der normale Online-Browser
                GameWebView(url: URL(string: game.sourceUrl)!, discoveredIframeUrl: $discoveredIframeUrl)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 16) {
                
                if downloader.isDownloading && !game.isDownloaded {
                    Text(downloader.statusText)
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }
                
                if !game.isDownloaded {
                    if discoveredIframeUrl != nil || downloader.isDownloading {
                        Button(action: {
                            if let url = discoveredIframeUrl {
                                Task {
                                    if let _ = await downloader.downloadGameAssets(fromIframeUrl: url, gameId: game.id) {
                                        game.iframeUrl = url
                                        game.isDownloaded = true
                                    }
                                }
                            }
                        }) {
                            if downloader.isDownloading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(4)
                                    .background(Circle().fill(.blue.opacity(0.8)))
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.white, .green.opacity(0.9))
                            }
                        }
                    }
                }
                
                Button(action: {
                    LocalServerManager.shared.stopServer()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6), .black.opacity(0.4))
                }
            }
            .padding(.top, 20)
            .padding(.trailing, 16)
        }
    }
    
    // NEU: Die UI-Funktion, die den Check aufruft und das UI steuert
    private func runUpdateCheckFlow() {
        isCheckingForUpdates = true
        
        Task {
            let updateInfo = await downloader.checkForUpdate(for: game)
            isCheckingForUpdates = false
            
            // Wir speichern die neuen Version-Tags ab
            game.gameVersion = updateInfo.newVersion ?? game.gameVersion
            game.lastModifiedHeader = updateInfo.newHeader ?? game.lastModifiedHeader
            
            if updateInfo.needsUpdate {
                // Crawler überschreibt die alten lokalen Dateien mit den neuen
                if let iframeUrl = game.iframeUrl {
                    let _ = await downloader.downloadGameAssets(fromIframeUrl: iframeUrl, gameId: game.id)
                }
            }
            
            // Update fertig (oder nicht nötig) -> Spiel starten!
            showGame = true
        }
    }
}

struct StoreBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var library: GameLibrary
    
    @State private var currentTitle: String = "Lade itch.io..."
    @State private var currentUrl: String = "https://itch.io/games/html5"
    
    // NEU: Interne States, um die gescrapten Daten zwischenzuspeichern
    @State private var currentDeveloper: String = "Unbekannt"
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
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
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

// MARK: - Brücke zum Store-Browser (Erweitert)

struct StoreWebView: UIViewRepresentable {
    let startUrl: URL
    @Binding var currentTitle: String
    @Binding var currentUrl: String
    @Binding var currentDeveloper: String
    @Binding var currentCoverUrl: String
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: StoreWebView
        
        init(_ parent: StoreWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // NEU: Winziges JavaScript-Skript extrahiert den Entwickler und die Cover-URL aus dem DOM von itch.io
            let jsScrapeScript = """
            (function() {
                var cover = document.querySelector('meta[property="og:image"]')?.getAttribute('content') || '';
                var dev = '';
                var userLink = document.querySelector('a.user_link') || document.querySelector('.game_info_panel a');
                if (userLink) {
                    dev = userLink.innerText.trim();
                } else {
                    var title = document.title;
                    if (title.includes(' by ')) {
                        dev = title.split(' by ').pop().trim();
                    }
                }
                return { "developer": dev, "coverUrl": cover };
            })()
            """
            
            webView.evaluateJavaScript(jsScrapeScript) { result, error in
                DispatchQueue.main.async {
                    if let dict = result as? [String: String] {
                        self.parent.currentDeveloper = dict["developer"] ?? "Unbekannt"
                        self.parent.currentCoverUrl = dict["coverUrl"] ?? ""
                        print("🕵️‍♂️ Scraper-Ergebnis -> Entwickler: \(self.parent.currentDeveloper), Cover: \(self.parent.currentCoverUrl)")
                    }
                    
                    if let title = webView.title {
                        self.parent.currentTitle = title.components(separatedBy: " by ").first ?? title
                    }
                    self.parent.currentUrl = webView.url?.absoluteString ?? ""
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            let request = URLRequest(url: startUrl)
            webView.load(request)
        }
    }
}
