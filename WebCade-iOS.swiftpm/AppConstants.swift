import Foundation

// MARK: - App-weite Konstanten

enum AppConstants {
    /// Gemeinsamer User-Agent-String für alle HTTP-Requests (iPad-Tarnung)
    static let userAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Port des lokalen Proxy-Servers
    static let serverPort: UInt16 = 8080

    /// Basis-URL des lokalen Servers
    static var serverBaseURL: URL {
        URL(string: "http://localhost:\(serverPort)")!
    }
}
