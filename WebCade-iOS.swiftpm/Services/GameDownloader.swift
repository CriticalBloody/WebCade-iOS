import Foundation
import SwiftSoup

@MainActor
@Observable
class GameDownloader {
    var isDownloading = false
    var downloadProgress: Double = 0.0
    var statusText: String = ""
    
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
                do {
                    try fileManager.removeItem(at: gameFolder)
                } catch {
                    AppLogger.error("Konnte Spielordner nicht löschen", error: error)
                }
            }
            try fileManager.createDirectory(at: gameFolder, withIntermediateDirectories: true)
            
            var pathsToDownload = Set<String>()
            self.statusText = String(localized: "Lade index.html...")
            
            var mainReq = URLRequest(url: iframeUrl)
            mainReq.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
            mainReq.setValue(iframeUrlString, forHTTPHeaderField: "Referer")
            mainReq.cachePolicy = .reloadIgnoringLocalCacheData // Immer frische Daten beim Download
            
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
            
            // Regex erkennt auch Backtick-Template-Strings und .webm/.webp (Ren'Py)
            let fileExtensions = "wasm|data|js|json|zip|pck|unityweb|mem|ogg|mp3|png|jpg|jpeg|webp|webm"
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
            let jsFiles = pathsToDownload.filter { $0.lowercased().hasSuffix(".js") }
            var savedFiles = Set<String>()
            
            self.statusText = String(localized: "Deep-Scan: \(jsFiles.count) JS-Dateien werden analysiert...")
            AppLogger.debug("Deep-Crawler: Scanne \(jsFiles.count) JS-Dateien auf Engine-Assets...")
            
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
                do {
                    if !fileManager.fileExists(atPath: localJsDir.path) {
                        try fileManager.createDirectory(at: localJsDir, withIntermediateDirectories: true)
                    }
                    try jsData.write(to: localJsPath)
                } catch {
                    AppLogger.warning("JS-Datei konnte nicht gespeichert werden: \(cleanJsPath)", error: error)
                }
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
            
            AppLogger.debug("Deep-Crawler: \(pathsToDownload.count) Assets total nach JS-Scan.")
            
            // PHASE 3: Alle verbleibenden Assets herunterladen (Parallelisiert & mit Retry)
            let allPaths = Array(pathsToDownload).sorted()
            let total = allPaths.count
            var downloadedCount = savedFiles.count
            
            // Threadsichere Kopie für die Hintergrund-Tasks (Swift 6 Concurrency)
            let localUserAgent = AppConstants.userAgent
            
            try await withThrowingTaskGroup(of: String.self) { group in
                for relPath in allPaths {
                    let cleanRelPath = relPath.components(separatedBy: "?").first ?? relPath
                    if savedFiles.contains(cleanRelPath) { continue }
                    
                    group.addTask {
                        guard let assetUrl = URL(string: relPath, relativeTo: baseUrl) else { return cleanRelPath }
                        let localAssetPath = gameFolder.appendingPathComponent(cleanRelPath)
                        let localAssetDir = localAssetPath.deletingLastPathComponent()
                        
                        if !FileManager.default.fileExists(atPath: localAssetDir.path) {
                            do {
                                try FileManager.default.createDirectory(at: localAssetDir, withIntermediateDirectories: true)
                            } catch {
                                AppLogger.error("Verzeichnis konnte nicht erstellt werden", error: error)
                            }
                        }
                        
                        var assetReq = URLRequest(url: assetUrl)
                        assetReq.setValue(localUserAgent, forHTTPHeaderField: "User-Agent")
                        assetReq.setValue(iframeUrlString, forHTTPHeaderField: "Referer")
                        
                        // 3x Retry-Logik für instabile Verbindungen
                        for attempt in 1...3 {
                            if let (assetData, _) = try? await URLSession.shared.data(for: assetReq) {
                                do {
                                    try assetData.write(to: localAssetPath)
                                } catch {
                                    AppLogger.error("Asset konnte nicht geschrieben werden", error: error)
                                }
                                break
                            }
                            if attempt < 3 { try? await Task.sleep(nanoseconds: 500_000_000) }
                        }
                        return cleanRelPath
                    }
                }
                
                for try await completedPath in group {
                    downloadedCount += 1
                    let fileName = URL(string: completedPath)?.lastPathComponent ?? completedPath
                    await MainActor.run {
                        self.downloadProgress = Double(downloadedCount) / Double(total)
                        self.statusText = String(localized: "Download \(downloadedCount)/\(total): \(fileName)")
                    }
                }
            }

            self.statusText = String(localized: "Initial-Download fertig!")
            return gameFolder.path
            
        } catch {
            AppLogger.error("Download fehlgeschlagen für Spiel \(gameId.uuidString)", error: error)
            self.statusText = String(localized: "Fehler beim Download")
            return nil
        }
    }
    
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
                AppLogger.info("Update gefunden via version.json: \(newVersion)")
                return (true, newVersion, game.lastModifiedHeader)
            }
            AppLogger.debug("version.json ist aktuell.")
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
                AppLogger.info("Update gefunden via Last-Modified: \(serverDateString)")
                return (true, game.gameVersion, serverDateString)
            }
            
            AppLogger.debug("itch.io Last-Modified Datum ist aktuell.")
            // Wir aktualisieren heimlich unseren Header, falls er noch leer war (beim allerersten Start)
            return (false, game.gameVersion, serverDateString)
        }
        
        return (false, nil, nil)
    }
}
