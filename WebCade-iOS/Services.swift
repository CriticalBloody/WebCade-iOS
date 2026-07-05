import Foundation
import SwiftUI
import Combine
@preconcurrency import SwiftSoup
@preconcurrency import Swifter

// MARK: - Manager & Services

@MainActor
class LocalServerManager: ObservableObject {
    static let shared = LocalServerManager()
    private var server = HttpServer()
    @Published var isRunning = false
    
    func startServer(for directoryPath: String, iframeUrlString: String?) {
        do {
            // Wir nutzen Swifters Standard-Server NICHT mehr, da er root-Dateien 
            // vom Proxy blockiert und falsche MIME-Typen für WASM sendet!
            // server["/:path"] = shareFilesFromDirectory(directoryPath) <-- KOMPLETT GELÖSCHT
            
            // NEU: Unser eigener, universeller "Super-Handler" für jede Datei!
            server.notFoundHandler = { request in
                let path = request.path
                let localFileUrl = URL(fileURLWithPath: directoryPath).appendingPathComponent(path)
                
                // Hilfsfunktion für extrem präzise MIME-Typen (Lebensrettend für WebAssembly!)
                func getMimeType(for path: String) -> String {
                    let lowerPath = path.lowercased()
                    if lowerPath.hasSuffix(".html") { return "text/html" }
                    if lowerPath.hasSuffix(".js") { return "application/javascript" }
                    if lowerPath.hasSuffix(".css") { return "text/css" }
                    if lowerPath.hasSuffix(".png") { return "image/png" }
                    if lowerPath.hasSuffix(".jpg") || lowerPath.hasSuffix(".jpeg") { return "image/jpeg" }
                    if lowerPath.hasSuffix(".json") { return "application/json" }
                    if lowerPath.hasSuffix(".m4a") { return "audio/mp4" }
                    if lowerPath.hasSuffix(".mp3") { return "audio/mpeg" }
                    if lowerPath.hasSuffix(".ogg") { return "audio/ogg" }
                    // Hier ist der Schlüssel für Ren'Py und Unity 6:
                    if lowerPath.hasSuffix(".wasm") { return "application/wasm" } 
                    return "application/octet-stream" // Für .data, .pck oder Unbekanntes
                }
                
                let mimeType = getMimeType(for: path)
                
                // 1. LOKALER ZUGRIFF: Existiert die Datei schon auf dem iPad?
                if FileManager.default.fileExists(atPath: localFileUrl.path) {
                    if let data = try? Data(contentsOf: localFileUrl) {
                        return .raw(200, "OK", ["Content-Type": mimeType]) { writer in
                            try? writer.write([UInt8](data))
                        }
                    }
                }
                
                // 2. PROXY ZUGRIFF: Datei fehlt lokal, wir laden sie live von itch.io nach!
                guard let iframeStr = iframeUrlString, let iframeUrl = URL(string: iframeStr) else {
                    return .notFound
                }
                
                let baseUrl = iframeUrl.deletingLastPathComponent()
                guard let encodedPath = path.dropFirst().description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let remoteUrl = URL(string: encodedPath, relativeTo: baseUrl) else {
                    return .notFound
                }
                
                print("🔄 PROXY: Lade dynamisch fehlende Datei -> \(path)")
                
                var req = URLRequest(url: remoteUrl)
                req.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
                req.setValue(iframeStr, forHTTPHeaderField: "Referer")
                
                let semaphore = DispatchSemaphore(value: 0)
                var fetchedData: Data?
                
                let task = URLSession.shared.dataTask(with: req) { data, response, _ in
                    if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                        fetchedData = data
                    } else if let httpRes = response as? HTTPURLResponse {
                        print("⚠️ PROXY HTTP-FEHLER: Status \(httpRes.statusCode) für \(path)")
                    }
                    semaphore.signal()
                }
                task.resume()
                // Timeout von 15 Sekunden verhindert Thread-Deadlock bei langsamen Verbindungen
                let waitResult = semaphore.wait(timeout: .now() + 15)
                if waitResult == .timedOut {
                    print("⏱ PROXY TIMEOUT: \(path) hat zu lange gebraucht.")
                    fetchedData = nil
                }
                
                if let data = fetchedData {
                    try? FileManager.default.createDirectory(at: localFileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: localFileUrl)
                    
                    return .raw(200, "OK", ["Content-Type": mimeType]) { writer in
                        try? writer.write([UInt8](data))
                    }
                }
                
                print("❌ PROXY FEHLSCHLAG: \(path) konnte nicht geladen werden.")
                return .notFound
            }
            
            try server.start(AppConstants.serverPort, forceIPv4: true)
            isRunning = true
            print("🚀 Lokaler Server (mit Caching Proxy) läuft auf \(AppConstants.serverBaseURL)")
        } catch {
            print("❌ Server-Start fehlgeschlagen: \(error)")
        }
    }
    
    func stopServer() {
        server.stop()
        isRunning = false
    }
}

// MARK: - Der echte File-Downloader (Deep Crawler)
@MainActor
class GameDownloader: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusText: String = ""
    
    func downloadGameAssets(fromIframeUrl iframeUrlString: String, gameId: UUID) async -> String? {
        self.isDownloading = true
        defer { self.isDownloading = false }
        
        guard let iframeUrl = URL(string: iframeUrlString) else { return nil }
        let baseUrl = iframeUrl.deletingLastPathComponent()
        
        let fileManager = FileManager.default
        guard let docsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let gameFolder = docsPath.appendingPathComponent(gameId.uuidString)
        
        do {
            if fileManager.fileExists(atPath: gameFolder.path) {
                try fileManager.removeItem(at: gameFolder)
            }
            try fileManager.createDirectory(at: gameFolder, withIntermediateDirectories: true)
            
            var pathsToDownload = Set<String>()
            self.statusText = "Lade index.html..."
            
            var mainReq = URLRequest(url: iframeUrl)
            mainReq.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
            mainReq.setValue(iframeUrlString, forHTTPHeaderField: "Referer")
            
            let (htmlData, _) = try await URLSession.shared.data(for: mainReq)
            let indexPath = gameFolder.appendingPathComponent("index.html")
            try htmlData.write(to: indexPath)
            
            guard let htmlString = String(data: htmlData, encoding: .utf8) else { return gameFolder.path }
            let document = try SwiftSoup.parse(htmlString, baseUrl.absoluteString)
            
            let elements = try document.select("script[src], link[href], img[src]")
            for element in elements.array() {
                let attr = element.tagName() == "link" ? "href" : "src"
                let relUrl = try element.attr(attr)
                if !relUrl.isEmpty && !relUrl.hasPrefix("http") && !relUrl.hasPrefix("//") {
                    pathsToDownload.insert(relUrl)
                }
            }
            
            // Regex erkennt auch Backtick-Template-Strings und .webm (Ren'Py Menü-Videos)
            let fileExtensions = "wasm|data|js|json|zip|pck|unityweb|mem|ogg|mp3|png|jpg|webm"
            let extRegex = try NSRegularExpression(pattern: "[\"'`]([^\"'`\\s]+\\.(\(fileExtensions)))[\"'`]")
            
            // PHASE 1: HTML-Scan (direkte Referenzen)
            let htmlMatches = extRegex.matches(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString))
            for match in htmlMatches {
                if let range = Range(match.range(at: 1), in: htmlString) {
                    let relUrl = String(htmlString[range])
                    if !relUrl.hasPrefix("http") { pathsToDownload.insert(relUrl) }
                }
            }
            
            // PHASE 2: JS Deep-Scan
            // Ren'Py, Unity etc. referenzieren große Engine-Dateien (.wasm, .data, .webm)
            // erst aus JS-Loader-Code heraus – diese werden hier aufgedeckt.
            // JS-Dateien werden sofort gespeichert, um Doppel-Downloads zu vermeiden.
            let jsFiles = pathsToDownload.filter { $0.lowercased().hasSuffix(".js") }
            var savedFiles = Set<String>()
            
            self.statusText = "Deep-Scan: \(jsFiles.count) JS-Dateien werden analysiert..."
            print("🔍 Deep-Crawler: Scanne \(jsFiles.count) JS-Dateien auf Engine-Assets...")
            
            for jsRelPath in jsFiles {
                let cleanJsPath = jsRelPath.components(separatedBy: "?").first ?? jsRelPath
                guard let jsUrl = URL(string: jsRelPath, relativeTo: baseUrl) else { continue }
                
                var jsReq = URLRequest(url: jsUrl)
                jsReq.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
                jsReq.setValue(iframeUrlString, forHTTPHeaderField: "Referer")
                
                guard let (jsData, _) = try? await URLSession.shared.data(for: jsReq) else { continue }
                
                // JS sofort speichern (verhindert doppelten Download in Phase 3)
                let localJsPath = gameFolder.appendingPathComponent(cleanJsPath)
                let localJsDir = localJsPath.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: localJsDir.path) {
                    try? fileManager.createDirectory(at: localJsDir, withIntermediateDirectories: true)
                }
                try? jsData.write(to: localJsPath)
                savedFiles.insert(cleanJsPath)
                
                // JS-Inhalt nach versteckten Engine-Assets scannen
                guard let jsString = String(data: jsData, encoding: .utf8) else { continue }
                let jsMatches = extRegex.matches(in: jsString, range: NSRange(jsString.startIndex..., in: jsString))
                for match in jsMatches {
                    if let range = Range(match.range(at: 1), in: jsString) {
                        let relUrl = String(jsString[range])
                        if !relUrl.hasPrefix("http") { pathsToDownload.insert(relUrl) }
                    }
                }
            }
            
            print("🔍 Deep-Crawler: \(pathsToDownload.count) Assets total nach JS-Scan.")
            
            // PHASE 3: Alle verbleibenden Assets herunterladen
            let allPaths = Array(pathsToDownload).sorted()
            let total = allPaths.count
            for (index, relPath) in allPaths.enumerated() {
                let cleanRelPath = relPath.components(separatedBy: "?").first ?? relPath
                
                // Bereits in Phase 2 gespeicherte JS-Dateien überspringen
                if savedFiles.contains(cleanRelPath) { continue }
                
                self.downloadProgress = Double(index) / Double(total)
                let fileName = URL(string: cleanRelPath)?.lastPathComponent ?? cleanRelPath
                self.statusText = "Download \(index + 1)/\(total): \(fileName)"
                
                guard let assetUrl = URL(string: relPath, relativeTo: baseUrl) else { continue }
                
                let localAssetPath = gameFolder.appendingPathComponent(cleanRelPath)
                let localAssetDir = localAssetPath.deletingLastPathComponent()
                
                if !fileManager.fileExists(atPath: localAssetDir.path) {
                    try fileManager.createDirectory(at: localAssetDir, withIntermediateDirectories: true)
                }
                
                // iPad-Tarnung für die Asset-Downloads
                var assetReq = URLRequest(url: assetUrl)
                assetReq.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
                assetReq.setValue(iframeUrlString, forHTTPHeaderField: "Referer")
                
                if let (assetData, _) = try? await URLSession.shared.data(for: assetReq) {
                    try? assetData.write(to: localAssetPath)
                }
            }
            
            self.statusText = "Initial-Download fertig!"
            return gameFolder.path
            
        } catch {
            self.statusText = "Fehler beim Download"
            return nil
        }
    } // <-- WICHTIG: Hier endet die downloadGameAssets Funktion!
    
    // NEU: Der intelligente Hybrid-Checker (steht jetzt korrekt auf eigener Ebene)
    func checkForUpdate(for game: WebGame) async -> (needsUpdate: Bool, newVersion: String?, newHeader: String?) {
        guard let iframeStr = game.iframeUrl, let iframeUrl = URL(string: iframeStr) else {
            return (false, nil, nil)
        }
        
        let baseUrl = iframeUrl.deletingLastPathComponent()
        
        // STUFE 1: Nach version.json suchen (Perfekt für eigene Engine-Builds)
        let versionUrl = baseUrl.appendingPathComponent("version.json")
        var request = URLRequest(url: versionUrl)
        request.timeoutInterval = 3.0 // Schneller Timeout, falls sie nicht existiert
        
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let newVersion = json["version"] {
            
            if game.gameVersion != newVersion {
                print("🔄 Update gefunden via version.json: \(newVersion)")
                return (true, newVersion, game.lastModifiedHeader)
            }
            print("✅ version.json ist aktuell.")
            return (false, newVersion, game.lastModifiedHeader)
        }
        
        // STUFE 2: Fallback auf HTTP HEAD Request (Der itch.io Standard)
        var headRequest = URLRequest(url: iframeUrl)
        headRequest.httpMethod = "HEAD" // Lädt NUR Metadaten, nicht die Datei!
        
        if let (_, response) = try? await URLSession.shared.data(for: headRequest),
           let httpRes = response as? HTTPURLResponse,
           let serverDateString = httpRes.allHeaderFields["Last-Modified"] as? String {
            
            // Haben wir das Spiel schon mal geladen und weicht das Server-Datum ab?
            if let localDate = game.lastModifiedHeader, localDate != serverDateString {
                print("🔄 Update gefunden via Last-Modified: \(serverDateString)")
                return (true, game.gameVersion, serverDateString)
            }
            
            print("✅ itch.io Last-Modified Datum ist aktuell.")
            // Wir aktualisieren heimlich unseren Header, falls er noch leer war (beim allerersten Start)
            return (false, game.gameVersion, serverDateString)
        }
        
        return (false, nil, nil)
    }
}
