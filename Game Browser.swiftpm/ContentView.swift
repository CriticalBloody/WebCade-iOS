import SwiftUI

// MARK: - UI Ansichten

struct ContentView: View {
    @StateObject private var serverManager = LocalServerManager.shared
    @StateObject private var library = GameLibrary()
    
    @State private var showingAddSheet = false 
    
    let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
    
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
                            Button(role: .destructive) {
                                library.deleteGame(withId: game.id)
                            } label: {
                                // HIER lag der Fehler: systemImage statt systemName!
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
            RoundedRectangle(cornerRadius: 16)
                .fill(game.coverColor.gradient)
                .aspectRatio(1.0, contentMode: .fit)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            Text(game.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 4)
            
            Text(game.developer)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct GamePlayerView: View {
    @Binding var game: WebGame
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var downloader = GameDownloader()
    @State private var discoveredIframeUrl: String? = nil
    
    var currentLocalPath: String {
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsPath.appendingPathComponent(game.id.uuidString).path
    }
    
    var body: some View {
        Group {
            if game.isDownloaded {
                GameWebView(url: URL(string: "http://localhost:8080/index.html")!, discoveredIframeUrl: .constant(nil))
                    .onAppear {
                        LocalServerManager.shared.startServer(for: currentLocalPath, iframeUrlString: game.iframeUrl)
                    }
            } else {
                GameWebView(url: URL(string: game.sourceUrl)!, discoveredIframeUrl: $discoveredIframeUrl)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 16) {
                
                if downloader.isDownloading {
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
}

struct StoreBrowserView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var library: GameLibrary
    
    @State private var currentTitle: String = "Lade itch.io..."
    @State private var currentUrl: String = "https://itch.io/games/html5"
    
    var isGamePage: Bool {
        return currentUrl.contains(".itch.io/")
    }
    
    var body: some View {
        NavigationStack {
            StoreWebView(
                startUrl: URL(string: "https://itch.io/games/html5")!,
                currentTitle: $currentTitle,
                currentUrl: $currentUrl
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
                        library.addGame(title: currentTitle, url: currentUrl)
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
