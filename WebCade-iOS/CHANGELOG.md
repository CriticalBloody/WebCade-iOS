# Changelog

All notable changes to WebCade-iOS are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Fixed
- **Iframe-Scraper Bug**: Der Scraper lud statt des Spiels den itch.io-Empfehlungsbanner herunter,
  da `document.querySelector('iframe')` den ersten (falschen) Iframe auf der Seite fand.
  Fix: Filtert jetzt explizit nach `html-classic.itch.zone` / `html.itch.zone` URLs.
- Interval-Polling von 1000ms auf 500ms reduziert für schnellere Spiel-Erkennung.

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
