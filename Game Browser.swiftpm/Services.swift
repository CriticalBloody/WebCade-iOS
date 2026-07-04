import Foundation
@preconcurrency import SwiftSoup
@preconcurrency import Swifter

// MARK: - Manager & Services

class LocalServerManager: ObservableObject {
    static let shared = LocalServerManager()
    private var server = HttpServer()
    @Published var isRunning = false
    
    // Ersetzt die alte startServer-Funktion in Services.swift
    func startServer(for directoryPath: String, iframeUrlString: String?) {
        do {
            server["/:path"] = shareFilesFromDirectory(directoryPath)
            
            if let iframeStr = iframeUrlString, let iframeUrl = URL(string: iframeStr) {
                let baseUrl = iframeUrl.deletingLastPathComponent()
                
                server.notFoundHandler = { request in
                    let path = request.path
                    
                    // URL-Encoding für Pfade mit Leerzeichen oder Sonderzeichen reparieren
                    guard let encodedPath = path.dropFirst().description.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let remoteUrl = URL(string: encodedPath, relativeTo: baseUrl) else {
                        return .notFound
                    }
                    
                    print("🔄 PROXY: Lade dynamisch fehlende Datei -> \(path)")
                    
                    var req = URLRequest(url: remoteUrl)
                    req.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                    req.setValue(iframeStr, forHTTPHeaderField: "Referer")
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    var fetchedData: Data?
                    
                    let task = URLSession.shared.dataTask(with: req) { data, response, _ in
                        // NEU: Wir akzeptieren ALLE erfolgreichen Codes (inklusive 206 für Audio-Streams!)
                        if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                            fetchedData = data
                        } else if let httpRes = response as? HTTPURLResponse {
                            print("⚠️ PROXY HTTP-FEHLER: Status \(httpRes.statusCode) für \(path)")
                        }
                        semaphore.signal()
                    }
                    task.resume()
                    semaphore.wait()
                    
                    if let data = fetchedData {
                        let localFileUrl = URL(fileURLWithPath: directoryPath).appendingPathComponent(path)
                        try? FileManager.default.createDirectory(at: localFileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? data.write(to: localFileUrl)
                        
                        // NEU: Audio-Typen hinzugefügt
                        var mimeType = "application/octet-stream"
                        let lowerPath = path.lowercased()
                        if lowerPath.hasSuffix(".js") { mimeType = "application/javascript" }
                        else if lowerPath.hasSuffix(".css") { mimeType = "text/css" }
                        else if lowerPath.hasSuffix(".png") { mimeType = "image/png" }
                        else if lowerPath.hasSuffix(".jpg") || lowerPath.hasSuffix(".jpeg") { mimeType = "image/jpeg" }
                        else if lowerPath.hasSuffix(".json") { mimeType = "application/json" }
                        else if lowerPath.hasSuffix(".m4a") { mimeType = "audio/mp4" }
                        else if lowerPath.hasSuffix(".mp3") { mimeType = "audio/mpeg" }
                        else if lowerPath.hasSuffix(".ogg") { mimeType = "audio/ogg" }
                        
                        return .raw(200, "OK", ["Content-Type": mimeType]) { writer in
                            try? writer.write([UInt8](data))
                        }
                    }
                    
                    print("❌ PROXY FEHLSCHLAG: \(path) konnte nicht geladen werden.")
                    return .notFound
                }
            }
            
            try server.start(8080, forceIPv4: true)
            isRunning = true
            print("🚀 Lokaler Server (mit Caching Proxy) läuft auf http://localhost:8080")
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
            
            // NEU: Die iPad-Tarnung für den Haupt-Download!
            var mainReq = URLRequest(url: iframeUrl)
            mainReq.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
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
            
            let fileExtensions = "wasm|data|js|json|zip|pck|unityweb|mem|ogg|mp3|png|jpg"
            let extRegex = try NSRegularExpression(pattern: "[\"']([^\"'\\s]+\\.(\(fileExtensions)))[\"']")
            
            let htmlMatches = extRegex.matches(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString))
            for match in htmlMatches {
                if let range = Range(match.range(at: 1), in: htmlString) {
                    let relUrl = String(htmlString[range])
                    if !relUrl.hasPrefix("http") { pathsToDownload.insert(relUrl) }
                }
            }
            
            let total = pathsToDownload.count
            for (index, relPath) in Array(pathsToDownload).sorted().enumerated() {
                self.downloadProgress = Double(index) / Double(total)
                self.statusText = "Pre-Fetch \(index + 1)/\(total)..." 
                
                guard let assetUrl = URL(string: relPath, relativeTo: baseUrl) else { continue }
                
                let cleanRelPath = relPath.components(separatedBy: "?").first ?? relPath
                let localAssetPath = gameFolder.appendingPathComponent(cleanRelPath)
                let localAssetDir = localAssetPath.deletingLastPathComponent()
                
                if !fileManager.fileExists(atPath: localAssetDir.path) {
                    try fileManager.createDirectory(at: localAssetDir, withIntermediateDirectories: true)
                }
                
                // NEU: Die iPad-Tarnung für die Asset-Downloads!
                var assetReq = URLRequest(url: assetUrl)
                assetReq.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
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
    }
}
