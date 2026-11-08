# AGENTS.md

Anleitung für KI-Agenten (Claude Code u. a.), die an diesem Projekt arbeiten. Diese Datei wird vom Agenten selbständig erweitert, wenn sich Konventionen oder Abläufe ändern.

## Projekt in einem Satz

SwiftUI-App „Wyychällerli“ (iOS 17+, Core Data mit CloudKit, MVVM) mit Multi-AI-Service für Wein-Empfehlungen über OpenAI, Gemini oder Anthropic. Details in [README.md](README.md).

## Sprache und Stil

- Kommunikation mit dem Nutzer auf **Deutsch** (Schweizer Schreibweise ist willkommen).
- Code-Kommentare und UI-Texte auf Deutsch (Quellsprache; Übersetzungen siehe „Sprachen“), Bezeichner (Typen, Variablen, Funktionen) auf Englisch.
- Deutsche Anführungszeichen in UI-Texten: „…“.
- **Schweizer Schreibweise, kein ß.** Gilt für UI-Texte, Kommentare, Prompts und diese Doku. Einzige Ausnahme: das Suchwort `"weiß"` in `HeuristicLabelParser.typeKeywords` – auf deutschen Etiketten steht es so gedruckt, und die Erkennung würde sonst Weissweine verpassen. Beide Schreibweisen stehen dort nebeneinander.
- Keine Emojis in Code oder UI.

## Tests

- **Target `WyychaellerliTests`**, Swift Testing (`@Test`, `#expect`), 244 Tests in 30 Suiten: Party-Abstimmung, Landesflaggen, Speiseabgleich, Doppelerkennung, Regal, Wein, Alkohol, Jahrgang, Weitergabe, Sprache, Scan-Fehler, Vorauswahl, Katalog, Strichcode, Ergänzungen, Katalogsuche. Die Sprachtests lösen mit ausdrücklicher Locale auf (Pluralformen, Wortstellung) und fassen die gespeicherte App-Sprache nicht an; `TestStack.makeContext()` setzt sie auf Deutsch, weil der Simulator sie zwischen Läufen behält. Laufen in unter einer Sekunde.
- Ausführen: `xcodebuild -project Wyychaellerli.xcodeproj -scheme Wyychaellerli -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`. Das Scheme liegt geteilt unter `xcshareddata/xcschemes/` und gehört ins Repo.
- **Core Data im Test**: `TestStack.makeContext()` gibt je Test einen frischen In-Memory-Stack ohne CloudKit (`PersistenceController(inMemory: true, useCloudKit: false)`). Nie einen geteilten Stack verwenden – sonst hängt ein Fehlschlag von der Reihenfolge ab.
- **Tests halten Entscheidungen fest, nicht nur Code.** Die Schwellen der Doppelerkennung, „Riserva ist ein anderer Wein“, „der Bestand ändert sich beim Zusammenführen nie“, „ohne Stimme kein Sieger“ – wer eine Zahl verschiebt, sieht sofort, welcher Fall kippt.
- Eine bekannte Grenze steht als eigener Test drin: `LabelPairingMatcher` vergleicht ganze Zeichenketten, nicht Wortstämme – „Lammfleisch“ trifft „Lammbraten“ **nicht**. Der Test hält das fest, damit es niemand versehentlich für einen Fehler hält; als Verbesserung wäre ein Stammvergleich ab vier Zeichen denkbar.
- Tests sind **keine** Vorbedingung für einen TestFlight-Build (siehe Release-Regeln), aber ein Fehlschlag gehört gemeldet.

## Build und Test

Projekt bauen (Simulator, ohne Team):

```bash
xcodebuild build -project Wyychaellerli.xcodeproj -scheme Wyychaellerli -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```

Schneller Typecheck aller Quellen (Swift 5 und Swift 6 strict concurrency müssen beide sauber sein):

```bash
find Wyychaellerli -name '*.swift' -print0 | xargs -0 xcrun -sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator -swift-version 6 -parse-as-library
```

Wichtig: Der Ordner `Preview Content` enthält ein Leerzeichen – Dateilisten immer mit `-print0 | xargs -0` übergeben.

UI-Änderungen im Simulator verifizieren (Simulator-Tool oder `xcrun simctl`). Für den Simulator-Build **nicht** `CODE_SIGNING_ALLOWED=NO` setzen, sonst fehlt die Keychain-Berechtigung und `SecItemAdd` schlägt mit -34018 fehl. Nach Tests mit Dummy-Keys aufräumen:

```bash
xcrun simctl uninstall <UDID> ch.sondinetwork.wyychaellerli && xcrun simctl keychain <UDID> reset
```

Neben den Unit-Tests (siehe „Tests“) lässt sich Logik ohne UI (Schema, Prompt, Decoding, Fehler-Klassifikation) mit einem kleinen macOS-Harness prüfen: `swiftc main.swift Wyychaellerli/Models/*.swift Wyychaellerli/Services/*.swift Wyychaellerli/Services/Providers/*.swift`.

## Projektstruktur und Regeln

- `Wyychaellerli/` ist ein **synchronisierter Ordner** im Xcode-Projekt: neue Dateien einfach im passenden Unterordner ablegen, kein Eintrag in `project.pbxproj` nötig.
- `project.pbxproj` nur bei Build-Settings anfassen (z. B. Entitlements); Xcode formatiert die Datei beim Öffnen um – das ist normal.
- **Namen und Kennungen** (die App hiess bis zur Umbenennung „Weinkeller“):
  - Angezeigter Name: **Wyychällerli**, gesetzt über `INFOPLIST_KEY_CFBundleDisplayName` in beiden Konfigurationen. Umlaute sind hier erlaubt.
  - Bundle-ID: **`ch.sondinetwork.wyychaellerli`**. Umlaute sind hier **nicht** erlaubt; Xcode meldet „invalid character in Bundle Identifier … only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.)“ und der Build läuft trotzdem durch – Signierung und App Store Connect würden ihn später abweisen.
  - **Auf der Platte alles ASCII**: Ordner `Wyychaellerli/`, `Wyychaellerli.xcodeproj`, Target und Scheme `Wyychaellerli`. Nur der angezeigte Name trägt den Umlaut. Das hält Build-Befehle, Pfade und Git frei von Normalisierungs- und Quoting-Fragen.
  - `CFBundleName` folgt `PRODUCT_NAME` und damit dem Target-Namen. Direkt setzen lässt es sich **nicht**: `INFOPLIST_KEY_CFBundleName` wird zwar als Build-Einstellung akzeptiert, aber vom Info.plist-Generator ignoriert, und ein Eintrag in `Config/Info.plist` wird von ihm überschrieben. Für die Anzeige ist ohnehin `CFBundleDisplayName` massgeblich.
  - Der Logger nutzt weiterhin `subsystem == "com.weinkeller.app"`. **So lassen**, sonst stimmen alle dokumentierten Log-Befehle nicht mehr.
- `Wyychaellerli/Wyychaellerli.entitlements` enthält `keychain-access-groups`, iCloud/CloudKit und den Container `iCloud.com.sondinetwork.weinkeller.app`; nicht entfernen. Die Keychain-Gruppe heisst noch `com.weinkeller.app` – **so lassen**: Sie funktioniert (Team-Präfix zählt), und eine Umbenennung würde die gespeicherten API-Keys unauffindbar machen.
- **Der iCloud-Container behält den alten Namen und darf nie geändert werden.** `iCloud.com.sondinetwork.weinkeller.app` hängt nicht an der Bundle-ID. Genau deshalb hat die Umbenennung die Daten nicht gekostet: Die neue App zieht denselben Container und damit den gesamten Keller samt Freigabe wieder herunter. Eine Änderung dieser Zeichenkette wäre gleichbedeutend mit Datenverlust.
- `Config/Info.plist` liegt **bewusst ausserhalb** des synchronisierten Ordners (sonst „Multiple commands produce Info.plist“). Xcode führt sie mit den generierten Keys zusammen (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Config/Info.plist`). Dort steht nur, was sich nicht als Build-Setting ausdrücken lässt, z. B. `UILaunchScreen/UIColorName`.
- Schema-Änderungen brauchen Migrationsüberlegungen, da bestehende Installationen Daten haben. Neue Attribute immer mit Standardwert (CloudKit-Pflicht).
- **Weintypen** (`WineType` in `Models/Wine.swift`): `red`, `white`, `sparkling`, `rose`, `mulled` (Glühwein und verwandte Winter-Heissgetränke). Der Rohwert steht als String am `Wine`, ein neuer Fall braucht deshalb keine Migration. Ein neuer Typ ist an fünf Stellen nachzuziehen: `displayName` und `symbolName` (Wine.swift), `color` (Theme.swift), `LabelSchema` (enum-Liste), `PromptBuilder.labelSystemPrompt`, `GeneratedWineLabel` (`@Guide`) und `HeuristicLabelParser.typeKeywords`. Bei den Stichwörtern zählt die **Reihenfolge**: Glühwein steht vor den Farbbegriffen, weil solche Etiketten fast immer zusätzlich „Rotwein“ oder „vin rouge“ nennen.

## Git-Workflow

Der Nutzer testet Änderungen selbst. Am Ende jeder Antwort mit Dateiänderungen einen fertigen Befehl liefern, den er per Klick ausführen kann:

```bash
git add . && git commit -m "Kurze deutsche Beschreibung" && git push
```

Nicht selbst committen oder pushen, sofern nicht ausdrücklich gewünscht.

## Weiterführende Anleitungen

Die Details zu einzelnen Bereichen liegen in `Docs/Agenten/`. **Vor der Arbeit an einem Bereich die passende Datei lesen** und bei Änderungen dort mitpflegen:

| Datei | Wann lesen |
|---|---|
| [Oberflaeche.md](Docs/Agenten/Oberflaeche.md) | Tableiste, Markenauftritt, Filter der Kellerliste, Farben, Detailseite, App-Icon, Startbild |
| [Sprachen.md](Docs/Agenten/Sprachen.md) | Neue Texte, `tr`, Plurale, eine weitere Sprache hinzufügen |
| [KI.md](Docs/Agenten/KI.md) | Apple Intelligence, Private Cloud, Berater, Anbieter, Prompts |
| [Etikett-Scan.md](Docs/Agenten/Etikett-Scan.md) | Texterkennung, Zuschnitt, Zuordnung, Jahrgang, Speisen vom Etikett |
| [Daten-und-Freigabe.md](Docs/Agenten/Daten-und-Freigabe.md) | Core Data, CloudKit, Schema-Deploy, Freigabe, DEV und TestFlight |
| [Keller-Funktionen.md](Docs/Agenten/Keller-Funktionen.md) | Doppelerkennung, Regal, Bewertungen, Trinkreife, Herkunftskarte, Siri, Teilen, Party, Einführung, Tipps, Stolperfallen |
| [Katalog-Betrieb.md](Docs/Agenten/Katalog-Betrieb.md) | Gemeinsamer Katalog, Admin-Bereich, Import, Quellenabgleich (Entwurf: [Docs/Katalog.md](Docs/Katalog.md)) |
| [Plattformen-und-Release.md](Docs/Agenten/Plattformen-und-Release.md) | Kein Mac, iPhone Duo, TestFlight, App Store Connect |

## Pflege dieser Datei

Wenn sich Konventionen, Build-Schritte oder Stolperfallen ändern, diese Datei oder die betroffene Datei in `Docs/Agenten/` im selben Änderungsschritt aktualisieren. **Diese Datei bleibt kurz**: nur, was jede Arbeit betrifft (Stil, Build, Tests, Namen und Kennungen, Git). Bereichswissen gehört in die Datei des Bereichs; eine neue Datei bekommt eine Zeile in der Tabelle oben.
