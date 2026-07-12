import Foundation
import Swifter

@MainActor
@Observable
class LocalServerManager {
    static let shared = LocalServerManager()
    private init() {} // Verhindert versehentliche Mehrfach-Instanziierung
    private var server = HttpServer()
    var isRunning = false
    
    // Begrenzte URLSession, um "NoMemory" Abstürze durch zu viele parallele Proxy-Anfragen beim Skippen zu verhindern
    private static let proxySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()
    
    // Strenges globales Limit für Proxy-Anfragen, um DNS NoMemory Abstürze des iOS mDNSResponders zu verhindern
    private static let proxyLimiter = DispatchSemaphore(value: 8)
    
    func startServer(for directoryPath: String, iframeUrlString: String?) {
        do {
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
                    if lowerPath.hasSuffix(".gif") { return "image/gif" }
                    if lowerPath.hasSuffix(".svg") { return "image/svg+xml" }
                    if lowerPath.hasSuffix(".webp") { return "image/webp" }
                    if lowerPath.hasSuffix(".json") { return "application/json" }
                    if lowerPath.hasSuffix(".m4a") { return "audio/mp4" }
                    if lowerPath.hasSuffix(".mp3") { return "audio/mpeg" }
                    if lowerPath.hasSuffix(".ogg") { return "audio/ogg" }
                    if lowerPath.hasSuffix(".wav") { return "audio/wav" }
                    if lowerPath.hasSuffix(".mp4") { return "video/mp4" }
                    if lowerPath.hasSuffix(".webm") { return "video/webm" }
                    // Hier ist der Schlüssel für Ren'Py und Unity 6:
                    if lowerPath.hasSuffix(".wasm") { return "application/wasm" } 
                    return "application/octet-stream" // Für .data, .pck oder Unbekanntes
                }
                
                let mimeType = getMimeType(for: path)
                
                // 1. LOKALER ZUGRIFF: Existiert die Datei schon auf dem iPad?
                if FileManager.default.fileExists(atPath: localFileUrl.path) {
                    // Dateigröße prüfen für Streaming-Entscheidung
                    let fileAttributes = try? FileManager.default.attributesOfItem(atPath: localFileUrl.path)
                    let fileSize = (fileAttributes?[.size] as? Int) ?? 0
                    let streamingThreshold = 5 * 1024 * 1024 // 5 MB
                    
                    var responseHeaders = ["Content-Type": mimeType, "Accept-Ranges": "bytes"]
                    
                    if request.method == "HEAD" {
                        responseHeaders["Content-Length"] = "\(fileSize)"
                        return .raw(200, "OK", responseHeaders) { _ in }
                    }
                    
                    // Range-Request Handling (für Audio/Video Streaming)
                    if let rangeHeader = request.headers["range"],
                       rangeHeader.hasPrefix("bytes="),
                       let rangeString = rangeHeader.components(separatedBy: "=").last {
                        let rangeComponents = rangeString.components(separatedBy: "-")
                        if let startString = rangeComponents.first, let start = Int(startString) {
                            let endString = rangeComponents.count > 1 ? rangeComponents[1] : ""
                            let end = Int(endString) ?? (fileSize - 1)
                            if start < fileSize && end < fileSize && start <= end {
                                guard let fileHandle = try? FileHandle(forReadingFrom: localFileUrl) else {
                                    return .notFound
                                }
                                defer { try? fileHandle.close() }
                                try? fileHandle.seek(toOffset: UInt64(start))
                                let chunkSize = end - start + 1
                                guard let chunk = try? fileHandle.read(upToCount: chunkSize) else {
                                    return .notFound
                                }
                                responseHeaders["Content-Range"] = "bytes \(start)-\(end)/\(fileSize)"
                                responseHeaders["Content-Length"] = "\(chunk.count)"
                                return .raw(206, "Partial Content", responseHeaders) { writer in
                                    try? writer.write([UInt8](chunk))
                                }
                            }
                        }
                    }
                    
                    responseHeaders["Content-Length"] = "\(fileSize)"
                    
                    // Große Dateien (>5MB): Chunk-weise streamen statt komplett in RAM laden
                    if fileSize > streamingThreshold {
                        return .raw(200, "OK", responseHeaders) { writer in
                            guard let fileHandle = try? FileHandle(forReadingFrom: localFileUrl) else { return }
                            defer { try? fileHandle.close() }
                            let chunkSize = 1024 * 1024 // 1 MB Chunks
                            while true {
                                guard let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                                try? writer.write([UInt8](chunk))
                            }
                        }
                    }
                    
                    // Kleine Dateien: Direkt in den RAM laden (schneller)
                    if let data = try? Data(contentsOf: localFileUrl) {
                        return .raw(200, "OK", responseHeaders) { writer in
                            try? writer.write([UInt8](data))
                        }
                    }
                }
                
                // 2. PROXY ZUGRIFF (Strikt Limitiert & Range Support)
                guard let iframeStr = iframeUrlString, let iframeUrl = URL(string: iframeStr) else {
                    return .notFound
                }
                
                let baseUrl = iframeUrl.deletingLastPathComponent()
                var queryStr = ""
                if !request.queryParams.isEmpty {
                    queryStr = "?" + request.queryParams.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
                }
                
                guard let encodedPath = (path.dropFirst().description + queryStr).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let remoteUrl = URL(string: encodedPath, relativeTo: baseUrl) else {
                    return .notFound
                }
                
                let waitResult = LocalServerManager.proxyLimiter.wait(timeout: .now() + 120)
                if waitResult == .timedOut {
                    AppLogger.warning("PROXY LIMIT: 429 Too Many Requests für \(path)")
                    return .raw(429, "Too Many Requests", [:]) { _ in }
                }
                defer { LocalServerManager.proxyLimiter.signal() }
                
                AppLogger.debug("PROXY DOWNLOAD: Lade \(path)\(queryStr)...")
                let semaphore = DispatchSemaphore(value: 0)
                var fetchedData: Data?
                var fetchedResponse: HTTPURLResponse?
                
                var req = URLRequest(url: remoteUrl)
                req.httpMethod = request.method
                req.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
                req.setValue(iframeStr, forHTTPHeaderField: "Referer")
                
                // Alle relevanten Header weiterleiten (besonders Range!)
                for (key, value) in request.headers {
                    let lowerKey = key.lowercased()
                    if lowerKey != "host" && lowerKey != "connection" {
                        req.setValue(value, forHTTPHeaderField: key)
                    }
                }
                
                let task = LocalServerManager.proxySession.dataTask(with: req) { data, response, _ in
                    fetchedResponse = response as? HTTPURLResponse
                    if let httpRes = fetchedResponse, (200...299).contains(httpRes.statusCode) {
                        fetchedData = data
                    }
                    semaphore.signal()
                }
                task.resume()
                
                if semaphore.wait(timeout: .now() + 60) == .timedOut {
                    task.cancel()
                    AppLogger.warning("PROXY TIMEOUT: \(path)")
                    return .notFound
                }
                
                if let httpRes = fetchedResponse {
                    let statusCode = httpRes.statusCode
                    let statusText = statusCode == 206 ? "Partial Content" : "OK"
                    var responseHeaders = ["Content-Type": httpRes.mimeType ?? mimeType]
                    
                    for (key, value) in httpRes.allHeaderFields {
                        if let keyString = key as? String, let valueString = value as? String {
                            // Einige Header wie Content-Encoding können Swifter stören, wenn wir sie blind kopieren
                            let lowerKey = keyString.lowercased()
                            if lowerKey != "content-encoding" && lowerKey != "transfer-encoding" {
                                responseHeaders[keyString] = valueString
                            }
                        }
                    }
                    
                    if let data = fetchedData {
                        // Nur den kompletten File lokal cachen (keine 206 Chunks speichern!)
                        if statusCode == 200 && request.method == "GET" {
                            do {
                                try FileManager.default.createDirectory(at: localFileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                                try data.write(to: localFileUrl)
                            } catch {
                                AppLogger.error("Proxy-Cache konnte nicht geschrieben werden: \(path)", error: error)
                            }
                        }
                        
                        if request.method == "HEAD" {
                            return .raw(statusCode, statusText, responseHeaders) { _ in }
                        }
                        
                        return .raw(statusCode, statusText, responseHeaders) { writer in
                            try? writer.write([UInt8](data))
                        }
                    } else if request.method == "HEAD" {
                        return .raw(statusCode, statusText, responseHeaders) { _ in }
                    }
                }
                
                return .notFound
            }
            
            try server.start(AppConstants.serverPort, forceIPv4: true)
            isRunning = true
            AppLogger.info("Lokaler Server (mit Caching Proxy) läuft auf \(AppConstants.serverBaseURL)")
        } catch {
            AppLogger.error("Server-Start fehlgeschlagen", error: error)
        }
    }
    
    func stopServer() {
        server.stop()
        isRunning = false
    }
}
