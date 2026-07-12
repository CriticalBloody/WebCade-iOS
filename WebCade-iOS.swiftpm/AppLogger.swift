import Foundation
import os

// MARK: - Zentraler App-Logger
// Ersetzt verstreute print() und stille try?-Aufrufe durch strukturiertes Logging.
// Nutzt Apples os.Logger für performantes, filterbares Logging im Xcode-Console.

public enum AppLogger: Sendable {
    private static let logger = Logger(subsystem: "de.larsitsolutions.webcade", category: "General")
    
    /// Informations-Log (normaler Ablauf)
    nonisolated public static func info(_ message: String) {
        logger.info("ℹ️ \(message)")
    }
    
    /// Warnung (unerwarteter aber nicht-kritischer Fehler)
    nonisolated public static func warning(_ message: String, error: Error? = nil) {
        if let error {
            logger.warning("⚠️ \(message): \(error.localizedDescription)")
        } else {
            logger.warning("⚠️ \(message)")
        }
    }
    
    /// Fehler (Operation fehlgeschlagen)
    nonisolated public static func error(_ message: String, error: Error? = nil) {
        if let error {
            logger.error("❌ \(message): \(error.localizedDescription)")
        } else {
            logger.error("❌ \(message)")
        }
    }
    
    /// Debug-only (nur in Debug-Builds sichtbar)
    nonisolated public static func debug(_ message: String) {
        #if DEBUG
        logger.debug("🔍 \(message)")
        #endif
    }
}
