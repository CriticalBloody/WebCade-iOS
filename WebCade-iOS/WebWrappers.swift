import Foundation
import SwiftUI
import WebKit

// MARK: - WebKit Logik

struct GameWebView: UIViewRepresentable {
    let url: URL
    @Binding var discoveredIframeUrl: String?
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: GameWebView
        
        init(_ parent: GameWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // 1. Savegame Handler
            if message.name == "savegameHandler" {
                if let body = message.body as? [String: Any],
                   let action = body["action"] as? String,
                   let key = body["key"] as? String,
                   let value = body["value"] as? String {
                    if action == "setItem" {
                        UserDefaults.standard.set(value, forKey: "webgame_\(key)")
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
        let allDefaults = UserDefaults.standard.dictionaryRepresentation()
        var jsCode = ""
        for (key, value) in allDefaults {
            if key.hasPrefix("webgame_") {
                let originalKey = key.replacingOccurrences(of: "webgame_", with: "")
                if let stringValue = value as? String {
                    // JSONSerialization erzeugt sicheres JSON-String-Literal (kein XSS via ')
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
        localStorage.setItem = function(key, value) {
            originalSetItem.apply(this, arguments);
            window.webkit.messageHandlers.savegameHandler.postMessage({
                action: 'setItem', key: key, value: value
            });
        };
        """
        let spyScript = WKUserScript(source: spyCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(spyScript)
        userContentController.add(context.coordinator, name: "savegameHandler")
        
        let scraperCode = """
        (function() {
            const intervalId = setInterval(function() {
                const iframe = document.querySelector('iframe');
                if (iframe && iframe.src) {
                    clearInterval(intervalId);
                    window.webkit.messageHandlers.scraperHandler.postMessage(iframe.src);
                }
            }, 1000);
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
}
