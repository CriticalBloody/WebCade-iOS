import SwiftUI
import WebKit

struct GamePlayerView: View {
    @Binding var game: WebGame
    @Environment(\.dismiss) var dismiss
    
    @State private var downloader = GameDownloader()
    @State private var discoveredIframeUrl: String? = nil
    @State private var errorMessage: String? = nil

    // Update-Status Variablen
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
                GameWebView(url: AppConstants.serverBaseURL.appendingPathComponent("index.html"), gameId: game.id, discoveredIframeUrl: .constant(nil))
            } else if game.isDownloaded {
                // Lade- und Update-Bildschirm mit Fortschrittsbalken
                ZStack {
                    Rectangle()
                        .fill(game.coverColor.gradient)
                        .ignoresSafeArea()

                    VStack(spacing: 28) {
                        // Spiel-Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.white.opacity(0.18))
                                .frame(width: 84, height: 84)
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 38))
                                .foregroundColor(.white)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)

                        Text(game.title)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if isCheckingForUpdates {
                            // Update-Check Phase
                            VStack(spacing: 14) {
                                ProgressView()
                                    .scaleEffect(1.4)
                                    .tint(.white)
                                Text(String(localized: "Prüfe auf Updates..."))
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        } else if downloader.isDownloading {
                            // Download Phase mit echtem Fortschrittsbalken
                            VStack(spacing: 14) {
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.25))
                                        .frame(width: 260, height: 8)
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: 260 * downloader.downloadProgress, height: 8)
                                        .animation(.linear(duration: 0.3), value: downloader.downloadProgress)
                                }

                                HStack {
                                    Text(downloader.statusText)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(downloader.downloadProgress * 100))%")
                                        .font(.caption.monospacedDigit().bold())
                                        .foregroundColor(.white)
                                }
                                .frame(width: 260)
                            }
                        } else {
                            // Start Phase
                            VStack(spacing: 14) {
                                ProgressView()
                                    .scaleEffect(1.4)
                                    .tint(.white)
                                Text(downloader.statusText.isEmpty ? String(localized: "Wird gestartet...") : downloader.statusText)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(32)
                }
                .task {
                    await runUpdateCheckFlow()
                }
            } else if let sourceUrl = URL(string: game.sourceUrl) {
                // Noch nie geladen: Der normale Online-Browser
                GameWebView(url: sourceUrl, gameId: game.id, discoveredIframeUrl: $discoveredIframeUrl)
            } else {
                // Ungültige URL – Fehler-Fallback
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(String(localized: "Ungültige Spiel-URL"))
                        .font(.headline)
                    Text(game.sourceUrl)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            LocalServerManager.shared.stopServer()
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .overlay(alignment: .top) {
            if let error = errorMessage {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(String(localized: "Download fehlgeschlagen"))
                            .bold()
                        Spacer()
                        Button {
                            withAnimation { errorMessage = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                        }
                    }
                    Text(error)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.red.opacity(0.9).gradient)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding()
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: errorMessage)
            }
        }
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
                                // Haptic Feedback beim Download-Start
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task {
                                    if let _ = await downloader.downloadGameAssets(fromIframeUrl: url, gameId: game.id) {
                                        game.iframeUrl = url
                                        
                                        // Holt sich direkt nach dem Download die aktuellen Header, um doppelte Downloads zu vermeiden!
                                        let updateInfo = await downloader.checkForUpdate(for: game)
                                        game.gameVersion = updateInfo.newVersion
                                        game.lastModifiedHeader = updateInfo.newHeader
                                        
                                        game.isDownloaded = true
                                        // Haptic Feedback bei Erfolg
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
    
    private func runUpdateCheckFlow() async {
        isCheckingForUpdates = true

        let updateInfo = await downloader.checkForUpdate(for: game)
        isCheckingForUpdates = false

        game.gameVersion = updateInfo.newVersion ?? game.gameVersion
        game.lastModifiedHeader = updateInfo.newHeader ?? game.lastModifiedHeader

        if updateInfo.needsUpdate {
            if let iframeUrl = game.iframeUrl {
                if await downloader.downloadGameAssets(fromIframeUrl: iframeUrl, gameId: game.id) == nil {
                    withAnimation {
                        errorMessage = String(localized: "Das Spiel-Update konnte nicht heruntergeladen werden.")
                    }
                }
            }
        }

        // WICHTIG: Server starten BEVOR die WKWebView gerendert wird!
        LocalServerManager.shared.startServer(for: currentLocalPath, iframeUrlString: game.iframeUrl)
        showGame = true
    }
}
