# WebCade-iOS 🎮

Eine native iPadOS-Anwendung, die es ermöglicht, browserbasierte HTML5-Spiele (wie z.B. von itch.io) lokal herunterzuladen und komplett offline zu spielen. 

Dieses Projekt löst komplexe Probleme beim Caching und der dynamischen Pfadgenerierung von Web-Engines (wie TyranoBuilder, Unity WebGL) auf restriktiven iOS-Geräten durch einen eigens implementierten lokalen Reverse-Proxy.

## ✨ Kern-Features

* **Intelligenter Caching-Proxy:** Ein lokaler `Swifter`-Webserver fängt fehlende Engine-Dateien (404-Fehler) zur Laufzeit ab, lädt sie asynchron mit einem Cloudflare-Bypass nach und füttert sie direkt ins laufende Spiel.
* **Cloudflare Stealth-Modus:** Integrierte `WKWebView` mit manipulierten User-Agent-Headern, um Bot-Protection-Systeme (wie Cloudflare Turnstile) beim Scraping zu umgehen.
* **Persistent Savegames:** Injiziert eigene JavaScript-Handler in den Browser-Storage, um flüchtige WebKit-Speicher auszutricksen und Spielstände dauerhaft in den iOS `UserDefaults` zu sichern.
* **Dynamisches Sandbox-Routing:** Berechnet Dateipfade bei jedem App-Start dynamisch neu, um Apples strikte Sandbox-Regeln für verschobene Dokumenten-Ordner zu respektieren.
* **Deep Crawler:** Analysiert `index.html` und verknüpfte `.js`-Dateien via RegEx auf versteckte Engine-Pakete (.data, .pck, .zip) für einen vollständigen Initial-Download.
* **Clean Storage Management:** Rückstandsloses Löschen von Spieldaten aus der iOS-Sandbox per nativem SwiftUI-Kontextmenü.

## 🛠 Technologien & Architektur

* **Swift 5 / SwiftUI** für die moderne, native Benutzeroberfläche.
* **WebKit (`WKWebView`)** als isolierte Laufzeitumgebung für die Spiele.
* **Swifter** als leichtgewichtiger, lokaler HTTP-Server.
* **SwiftSoup** für das zuverlässige DOM-Parsing und Scraping der Assets.

## 🚀 Installation & Nutzung (Swift Playgrounds)

Da dieses Projekt direkt für **Swift Playgrounds auf dem iPad** konzipiert wurde, ist keine externe Xcode-Umgebung zwingend erforderlich.

1. Lade dir das Repository als `.zip` herunter oder klone es.
2. Öffne den Projektordner in der App *Swift Playgrounds* auf dem iPad (oder in Xcode auf dem Mac).
3. Warte, bis die Swift Packages (`Swifter`, `SwiftSoup`) im Hintergrund geladen wurden.
4. Führe die App aus. 
5. Über das `+` Symbol kannst du HTML5-Spiele ansteuern und herunterladen.

## 📝 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert.

Copyright (c) 2026 Lars Taube / Lars IT Solutions

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
