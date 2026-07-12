# Changelog

All notable changes to WebCade-iOS are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [0.3.0] – 2026-07-09

### Added
- **Fehler-UI**: Neues, ansprechendes Fehler-Banner im `GamePlayerView` statt störender System-Alerts.
- **Lokalisierung**: Komplette App-UI ist nun für Xcode String-Catalogs vorbereitet (via `String(localized:)`).
- **Haptic Feedback**: Tastbares Feedback bei wichtigen Aktionen (Download Start/Ende, Spiel löschen, Pull-to-Refresh).
- **UX Verbesserungen**: Skeleton-Loading im Bibliotheks-Grid und Pull-to-Refresh hinzugefügt.
- **Sicherheitsabfrage**: `.confirmationDialog` verhindert versehentliches Löschen von Spielen.
- **Unit Tests**: `GameLibraryTests` und `CrawlerTests` hinzugefügt, um WebScraper-Regex und Persistenz abzusichern.

### Fixed
- **WKWebView Memory Leak**: Retain-Cycle bei `WKUserContentController` durch Implementierung von `dismantleUIView` gestopft.
- **OOM (Out Of Memory) Crashes**: `Data(contentsOf:)` durch effizientes `FileHandle`-Streaming (1MB Chunks) ersetzt. Große Assets (WASM/PCK) laden nun ohne RAM-Spikes.
- **Force-Unwrap Crashes**: Ungültige URLs lassen die App nicht mehr abstürzen.
- **Start-Timing-Bug**: Lokaler Proxy-Server startet nun garantiert synchron *bevor* die WebView gerendert wird. Verhindert Fehler beim ersten Laden eines Spiels.
- **Update-Check-Loop**: Initialer Download speichert nun sofort die HTTP-Header. Verhindert doppelte Downloads direkt nach der Installation.
- **Swift 6 Concurrency**: `AppLogger` auf `@Sendable` / `nonisolated` umgestellt, um strikte MainActor-Warnungen im Xcode 16 Compiler zu fixen.

### Changed
- **Architektur-Refactoring (God-Files)**: Die massiven Dateien `ContentView.swift` und `Services.swift` wurden komplett aufgelöst. Saubere Ordnerstruktur mit `Core/`, `Views/`, `Services/` und `Tests/` etabliert.
- **Datenmodellierung**: Migration von `@StateObject`/`ObservableObject` auf Apples hochperformantes `@Observable` Makro (iOS 17+).
- **Navigation**: `NavigationLink` lazy loading implementiert via `.navigationDestination`, um RAM zu sparen.
- **Dateisystem**: Das gesamte Projekt nutzt nun Xcodes automatische `PBXFileSystemSynchronizedRootGroup`. Neue Dateien müssen nicht mehr manuell in die `pbxproj` registriert werden. Both Targets (Xcode und Playgrounds) sind synchron.

---

## [0.2.0] – 2026-07-06

### Added
- **AppConstants.swift**: Zentrale Konstanten für User-Agent-String und Server-Port.
  Eliminiert 4-fache Code-Duplikation aus allen Dateien.
- **GameColor Enum**: Typsicheres Enum ersetzt fehleranfälligen String-Switch für Spielkarten-Farben.
- **Dreistufiger Deep-Crawler** für vollständigere Spiel-Downloads:
  - **Phase 1** – HTML-Scan via SwiftSoup + erweitertem Regex
  - **Phase 2** – JS-Dateien werden heruntergeladen und auf versteckte Engine-Assets gescannt
    (Ren'Py `.wasm`/`.data`, Unity `.pck`, Menü-Videos `.webm`)
  - **Phase 3** – Alle verbleibenden Assets werden geladen; bereits gespeicherte JS-Dateien werden übersprungen
- Download-Status zeigt jetzt den Dateinamen an statt generischem Zähler (`renpy.wasm` statt `Pre-Fetch 4/12`)
- Regex erkennt nun Backtick-Template-Strings und `.webm`-Dateien

### Fixed
- **Semaphore-Deadlock**: `DispatchSemaphore.wait()` hat 15-Sekunden-Timeout erhalten.
  Verhindert Thread-Deadlock bei langsamen Verbindungen im Proxy-Handler.
- **XSS in JS-Injection**: `localStorage.setItem`-Werte werden jetzt via `JSONSerialization`
  sicher enkodiert statt manuellem Escapen von einfachen Anführungszeichen.
- **Memory Leak**: `setInterval` im Iframe-Scraper wird jetzt mit `clearInterval` gestoppt
  sobald das Spiel-Iframe gefunden wurde.

### Changed
- Bibliotheks-Persistenz von `UserDefaults` (1 MB Limit) auf JSON-Datei im Documents-Ordner
  umgestellt – kein Datenverlust mehr bei vielen Spielen.
- `MyApp` → `WebCadeApp` umbenannt (war noch der Swift Playgrounds Default-Name).
- Unnötige `import Combine` Anweisungen aus allen View-Dateien entfernt.
- `.ipa` und `.dSYM` zu `.gitignore` hinzugefügt; kompiliertes Binary aus Repository entfernt.

---

## [0.1.3] – 2026-07-04

### Added
- Erstes öffentliches Beta-Release
- Intelligenter Caching-Proxy via Swifter-Webserver
- Cloudflare Stealth-Modus (manipulierter User-Agent)
- Persistente Savegames via JavaScript-Injection in WebKit-localStorage
- Dynamisches Sandbox-Routing für iOS-Dokumentenpfade
- Deep-Crawler mit SwiftSoup + Regex für initiale Asset-Erkennung
- Update-Check via `version.json` (Unity) und HTTP `Last-Modified`-Header (itch.io)
- Unterstützung für Ren'Py, Unity WebGL, TyranoBuilder und andere HTML5-Engines
- Clean Storage Management via SwiftUI-Kontextmenü
