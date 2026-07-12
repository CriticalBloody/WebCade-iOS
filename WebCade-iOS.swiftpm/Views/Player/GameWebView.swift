import Foundation
import SwiftUI
import WebKit

// MARK: - WebKit Logik

struct GameWebView: UIViewRepresentable {
    let url: URL
    let gameId: UUID?
    @Binding var discoveredIframeUrl: String?
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: GameWebView
        
        init(_ parent: GameWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // 1. Savegame Handler (Asynchrones Schreiben in Dateien)
            if message.name == "savegameHandler" {
                if let body = message.body as? [String: Any],
                   let action = body["action"] as? String,
                   let key = body["key"] as? String,
                   let value = body["value"] as? String,
                   let gameId = self.parent.gameId {
                    if action == "setItem" {
                        Task.detached(priority: .background) {
                            let fileManager = FileManager.default
                            if let docsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                                let savesDir = docsPath.appendingPathComponent(gameId.uuidString).appendingPathComponent("saves")
                                if !fileManager.fileExists(atPath: savesDir.path) {
                                    do {
                                        try fileManager.createDirectory(at: savesDir, withIntermediateDirectories: true)
                                    } catch {
                                        AppLogger.error("Save-Verzeichnis konnte nicht erstellt werden", error: error)
                                    }
                                }
                                
                                // Clean key for safe filename
                                let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
                                let fileUrl = savesDir.appendingPathComponent("\(safeKey).txt")
                                do {
                                    try value.write(to: fileUrl, atomically: true, encoding: .utf8)
                                    AppLogger.debug("Savegame geschrieben: \(safeKey)")
                                } catch {
                                    AppLogger.error("Savegame konnte nicht geschrieben werden: \(safeKey)", error: error)
                                }
                            }
                        }
                    }
                }
            }
            
            // 2. Scraper Handler
            if message.name == "scraperHandler" {
                if let urlString = message.body as? String {
                    DispatchQueue.main.async {
                        if self.parent.discoveredIframeUrl != urlString {
                            self.parent.discoveredIframeUrl = urlString
                            print("🕵️‍♂️ BINGO! Iframe im Hintergrund gefunden: \(urlString)")
                        }
                    }
                }
            }
            
            // 3. Console Handler
            if message.name == "consoleHandler" {
                if let log = message.body as? String {
                    if log.contains("ERROR:") || log.contains("EXCEPTION:") || log.contains("404") {
                        print("🚨 BROWSER-CRASH: \(log)")
                    } else {
                        print("🌐 Browser: \(log)")
                    }
                }
            }
        } // <-- Diese Klammer hatte vorhin gefehlt!
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func buildStorageInjectionCode() -> String {
        guard let gameId = gameId else { return "" }
        let fileManager = FileManager.default
        guard let docsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return "" }
        let savesDir = docsPath.appendingPathComponent(gameId.uuidString).appendingPathComponent("saves")
        
        var jsCode = ""
        if let files = try? fileManager.contentsOfDirectory(atPath: savesDir.path) {
            for file in files where file.hasSuffix(".txt") {
                let safeKey = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                let originalKey = safeKey.removingPercentEncoding ?? safeKey
                let fileUrl = savesDir.appendingPathComponent(file)
                
                if let stringValue = try? String(contentsOf: fileUrl, encoding: .utf8) {
                    if let keyData   = try? JSONSerialization.data(withJSONObject: originalKey),
                       let valData   = try? JSONSerialization.data(withJSONObject: stringValue),
                       let keyJson   = String(data: keyData, encoding: .utf8),
                       let valJson   = String(data: valData, encoding: .utf8) {
                        jsCode += "localStorage.setItem(\(keyJson), \(valJson));\n"
                    }
                }
            }
        }
        return jsCode
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        
        let existingSavesCode = buildStorageInjectionCode()
        if !existingSavesCode.isEmpty {
            let loadScript = WKUserScript(source: existingSavesCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(loadScript)
        }
        
        let spyCode = """
        const originalSetItem = localStorage.setItem;
        const pendingSaves = {};
        localStorage.setItem = function(key, value) {
            originalSetItem.apply(this, arguments);
            if (!pendingSaves[key]) {
                // 3000ms debounce prevents crashing from rapid skipping
                pendingSaves[key] = setTimeout(function() {
                    window.webkit.messageHandlers.savegameHandler.postMessage({
                        action: 'setItem', key: key, value: localStorage.getItem(key)
                    });
                    delete pendingSaves[key];
                }, 3000);
            }
        };
        """
        let spyScript = WKUserScript(source: spyCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(spyScript)
        userContentController.add(context.coordinator, name: "savegameHandler")
        
        let scraperCode = """
        (function() {
            const intervalId = setInterval(function() {
                const iframes = document.querySelectorAll('iframe');
                for (const iframe of iframes) {
                    // Nur echte Spiel-Iframes akzeptieren (nicht Empfehlungsbanner!)
                    if (iframe.src &&
                        (iframe.src.includes('html-classic.itch.zone') ||
                         iframe.src.includes('html.itch.zone'))) {
                        clearInterval(intervalId);
                        window.webkit.messageHandlers.scraperHandler.postMessage(iframe.src);
                        break;
                    }
                }
            }, 500);
        })();
        """
        let scraperScript = WKUserScript(source: scraperCode, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(scraperScript)
        userContentController.add(context.coordinator, name: "scraperHandler")
        
        let consoleCode = """
        const originalLog = console.log;
        const originalWarn = console.warn;
        const originalError = console.error;
        
        console.log = function() {
            const msg = Array.from(arguments).join(' ');
            window.webkit.messageHandlers.consoleHandler.postMessage('LOG: ' + msg);
            originalLog.apply(console, arguments);
        };
        console.warn = function() {
            const msg = Array.from(arguments).join(' ');
            window.webkit.messageHandlers.consoleHandler.postMessage('WARN: ' + msg);
            originalWarn.apply(console, arguments);
        };
        console.error = function() {
            const msg = Array.from(arguments).join(' ');
            window.webkit.messageHandlers.consoleHandler.postMessage('ERROR: ' + msg);
            originalError.apply(console, arguments);
        };
        window.onerror = function(message, source, lineno, colno, error) {
            window.webkit.messageHandlers.consoleHandler.postMessage('EXCEPTION: ' + message + ' (' + source + ':' + lineno + ')');
        };
        """
        let consoleScript = WKUserScript(source: consoleCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(consoleScript)
        userContentController.add(context.coordinator, name: "consoleHandler")
        
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        
        // --- REZEPT GEGEN DEN SCHWARZEN VIDEOPLAYER ---
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // ----------------------------------------------
        
        if #available(iOS 15.4, *) { config.preferences.isElementFullscreenEnabled = true }
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Die Safari-Tarnkappe für unseren Game-Player!
        webView.customUserAgent = AppConstants.userAgent
        webView.navigationDelegate = context.coordinator
        
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if webView.url == nil {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    // MARK: - Memory Leak Fix
    // WKUserContentController.add(_:name:) hält eine strong reference auf den Coordinator.
    // Ohne Cleanup entsteht ein Retain-Cycle: WebView → Config → Controller → Coordinator → Parent
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
    }
}
