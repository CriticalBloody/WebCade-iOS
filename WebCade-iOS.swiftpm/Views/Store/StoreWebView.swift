import SwiftUI
import WebKit

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
                        if !self.parent.currentDeveloper.isEmpty {
                            AppLogger.debug("Scraper-Ergebnis -> Entwickler: \(self.parent.currentDeveloper), Cover: \(self.parent.currentCoverUrl)")
                        }
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
        webView.customUserAgent = AppConstants.userAgent
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
