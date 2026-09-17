# Wyychällerli

Privater Weinkeller-Assistent für iPhone und iPad. Verwaltet den Flaschenbestand und schlägt zum geplanten Essen die passenden Weine aus dem eigenen Keller vor – wahlweise über ChatGPT (OpenAI), Gemini (Google) oder Claude (Anthropic).

## Funktionen

- **Bestand** – Flaschen mit Name, Jahrgang, Rebsorte/Region, Typ (Rot, Weiss, Schaum, Rosé, Glühwein) und Bestand. Schnell-Abbuchung per Minus-Button, Filter nach Typ, Suche, Archiv. Bei der letzten Flasche fragt die App, ob der Wein archiviert oder gelöscht werden soll.
- **Speiseempfehlung vom Etikett** – Steht auf dem Etikett, wozu der Wein passt, wird das beim Scannen übernommen und ins Deutsche übersetzt. Übernommen wird sie nur, wenn sie wirklich auf dem Etikett steht: Die KI muss die betreffende Stelle wörtlich mitliefern, und die App sucht sie im erkannten Text. Findet sie den Beleg nicht, wird die Empfehlung verworfen, statt „laut Etikett“ zu behaupten. Der Wein-Berater prüft zuerst diese Angaben: Nennt ein Etikett das Gericht ausdrücklich, erscheint der Treffer sofort, ohne KI-Anfrage und ohne Kosten. Erst wenn nichts passt, wird die KI gefragt. Steht nichts auf dem Etikett, bleibt der Abschnitt ausgeblendet.
- **Herkunftskarte** – Die Detailseite zeigt einen Kartenausschnitt mit Stecknadel auf der Weinregion, ermittelt aus Region und Land des Etiketts. Ist die Region nicht eindeutig auffindbar, zeigt die Karte nur das Land statt einer falschen Nadel. Ein Tipp öffnet Apple Karten. In der Liste und auf der Detailseite steht zudem die Landesflagge beim Wein, egal ob das Land als „Frankreich“, „France“ oder „Francia“ erfasst ist.
- **Wein-Berater** – Essens-Stichwort eingeben (z. B. „Raclette“), die KI liefert bis zu drei Empfehlungen aus dem aktuellen Bestand mit ehrlicher Passung (Perfekt, passt gut, geht, Notlösung), Begründung und Serviertipp. Passt nichts wirklich, sagt sie das offen und nennt, was klassisch passen würde, als Kauftipp. „Details“ öffnet die Detailseite, „Trinken“ bucht direkt ab – mit demselben Ablauf wie in der Liste: Fach wählen, wenn alles im Regal liegt, und bei der letzten Flasche die Frage nach Bewerten, Archiv oder Löschen. Antworten werden auf Plausibilität geprüft (nur Weine aus dem Keller, keine Platzhalter) und bei Bedarf einmal automatisch wiederholt.
- **Etikett scannen** – Vorderseite und Rückseite sind je eine eigene Fläche; ein Tipp darauf öffnet die Kamera für genau diese Seite, sodass die Reihenfolge frei wählbar ist. Die Flasche wird einfach ganz fotografiert, ohne Ausrichten. Die Etikettenkante findet die App danach selbst, schneidet frei und stellt das Bild aufrecht – das funktioniert auch bei dunklen Etiketten auf dunklem, rundem Glas und bei schwachem Kellerlicht. Alternativ Fotos aus der Mediathek wählen. Für dunkle Etiketten wertet die App jedes Foto zusätzlich in einer kontrastverstärkten und einer aufgehellten Fassung aus und übernimmt das beste Ergebnis. Die App liest den Text auf dem Gerät aus (Vision) und füllt Name, Produzent, Jahrgang, Rebsorten, Region, Typ und Notizen vor. Die Zuordnung macht Apple Intelligence auf dem Gerät (iOS 26, iPhone 15 Pro und neuer), sonst der aktive KI-Anbieter (es wird nur der erkannte Text gesendet, nie das Foto), sonst eine regelbasierte Erkennung. Notizen landen immer auf Deutsch in der App: Steht auf der Rückseite Französisch oder Italienisch, wird übersetzt, wenn möglich direkt auf dem Gerät und ohne Kosten. Läuft die Schrift um eine schmale Flasche herum, lassen sich je Seite bis zu drei weitere Ansichten fotografieren – von links und rechts –, deren Text zusammengeführt wird. Ovale und runde Etiketten werden über ihren Umriss zugeschnitten. Beide Etikettseiten werden zugeschnitten gespeichert; auf der Detailseite öffnet eine Lupe das Foto im Vollbild zum Zoomen. Die Vorderseite erscheint in der Liste und in den Empfehlungen, damit die Flasche im Regal schnell gefunden ist; auf der Detailseite wechselt eine Wischgeste zur Rückseite, wo Terroir, Ausbau und Speiseempfehlungen stehen.
- **Siri** – „Hey Siri, Wein-Berater in Wyychällerli“. Siri fragt nach dem Essen, liest die Empfehlung vor und zeigt eine Karte mit Etikett. Funktioniert auch über CarPlay und in der Kurzbefehle-App. Für Siri wird ein schnelleres Modell verwendet, da Siri nicht lange wartet.
- **Mehrere Regale** – Bis zu vier Regale je Keller, für verschiedene Orte: Keller, Küche, Garage. Umgeschaltet wird über den Namen im Titel der Regalansicht. Sobald es mehr als eines gibt, trägt jedes Fach den Regalnamen – „Küche · B3“ statt nur „B3“ –, damit niemand am falschen Ort sucht. Eine Flasche desselben Weins kann in einem Regal liegen, die zweite anderswo.
- **Alkoholgehalt** – Wird beim Scannen vom Etikett übernommen und als eigenes Feld geführt. In der Liste steht er zuunterst mit einem Tacho-Symbol, sodass man auf einen Blick sieht, ob eine Flasche leicht (unter 12 %), mittel (bis 13,5 %) oder kräftig ist – ohne dass die Herkunft darüber Platz verliert. Danach lässt sich auch filtern – „heute nur etwas Leichtes“. Ohne Angabe wird nichts behauptet.
- **Weine weiterempfehlen** – Auf der Detailseite teilt ein Knopf den Wein: Etikettfoto, die wichtigsten Angaben und ein eigener Hinweis („Gibt's bei Denner für 12.90“), verschickt per Nachricht, Mail oder wie auch immer. Auf Wunsch hängt eine kleine Datei mit allen Feldern an: Wer Wyychällerli hat, tippt sie an und hat den Wein samt Etikett, Notizen und Trinkreife im eigenen Keller – mit Hinweis, falls er ihn schon besitzt.
- **Party-Modus** – Gäste stimmen ab, welche Flasche geöffnet wird. Der Gastgeber startet den Modus mit einem Code, wählt die Flaschen zur Wahl und erfasst die Anwesenden; dann wandert das Gerät von Hand zu Hand. Jeder bekommt so viele Stimmen, wie zur Zahl der Flaschen passt (höchstens eine je Flasche), und sieht dabei weder den Zwischenstand noch eure eigenen Bewertungen. Am Schluss steht die Siegerflasche auf dem Podest, mit Konfettiregen – bei Gleichstand entscheidet vorher eine sichtbare Auslosung. Das Ergebnis wandert mit Anlass und Datum in die Party-Historie. Verlassen lässt sich der Modus nur mit Face ID, Touch ID oder dem Gerätecode – es ist nichts einzurichten und nichts zusätzlich zu merken. Vor dem Weitergeben erinnert die App an den geführten Zugriff von iOS (dreimal Seitentaste), der das Gerät ganz auf die App festnagelt, und zeigt an, sobald er läuft. Die Historie gehört zum Keller: Die vergangenen Siegerflaschen sind auf allen Geräten gleich zu sehen.
- **Einführung** – Beim ersten Start erklären sechs Seiten mit gezeichneten Bildern das Wichtigste: Scannen, Bestand, Regal, Berater und Teilen. Unter Einstellungen → Hilfe lässt sie sich jederzeit nochmals anzeigen. Dazu kommen kleine Tipps am Ort – beim ersten Abbuchen, Scannen, im Regal und am Etikett –, die nach dem ersten Mal verschwinden und sich in den Einstellungen zurückholen lassen.
- **Regal** – Ein Raster aus Ebenen und Fächern, frei einstellbar. Auf der Detailseite eines Weins pulsieren seine Fächer, sodass du vor dem Regal sofort siehst, wo die nächste Flasche liegt. Ein Tipp darauf entnimmt sie: Der Bestand geht um eins runter und der Platz wird frei für den nächsten Wein. Sind alle Flaschen verortet, führt auch der Minus-Knopf ins Regal, damit klar ist, welche Flasche gemeint ist. Eingeräumt wird entweder vom Wein aus oder über die Regalansicht, indem du ein freies Fach antippst. Hat ein Wein mehrere Flaschen, wischst du einfach über die freien Fächer und räumst alle auf einmal ein; mehr als du Flaschen hast, lässt sich nicht auswählen.
- **Doppelte Flaschen** – Wer einen Wein nachkauft und das Etikett scannt, sieht sofort im Formular, dass es ihn schon gibt, samt aktuellem Bestand. Die Suche schliesst archivierte und ausgetrunkene Einträge ein, denn gerade dort weiss man es nicht mehr auswendig. Ein Tipp bucht auf den bestehenden Eintrag und holt ihn nötigenfalls aus dem Archiv zurück. Kleine Abweichungen in der Schreibweise stören nicht, ein anderer Jahrgang gilt aber immer als anderer Wein.
- **Bewertungen** – Jede Person bewertet einen Wein für sich, mit fünf Sternen in halben Schritten, dazu optional Gründe zum Antippen wie „zu sauer“ oder „harmonisch“ und eine Notiz. Auf der Detailseite stehen beide Bewertungen einzeln plus das gemeinsame Ergebnis, und daraus folgt ein Kaufhinweis. Solange erst eine Person bewertet hat, sagt die App das ausdrücklich. Eine Übersicht listet alle bewerteten Weine nach Kaufhinweis gruppiert, auch die schon ausgetrunkenen. Der Wein-Berater gewichtet die Bewertungen mit, schliesst aber nichts aus.
- **Trinkreife** – Beim Scannen schätzt die KI aus Jahrgang, Rebsorte und Region, wann der Wein am besten getrunken wird; steht die Spanne auf dem Etikett, wird sie übernommen. Die App sagt immer dazu, was davon geschätzt ist. Flaschen, die dieses Jahr dran sind oder es schon länger wären, tragen einen Hinweis in der Liste, und ein Filter zeigt nur diese. Der Wein-Berater bevorzugt sie bei sonst gleicher Eignung.
- **Erscheinungsbild** – In den Einstellungen wählbar zwischen System, Hell und Dunkel. Die Wahl gilt nur für dieses Gerät, damit iPhone und iPad unterschiedlich eingestellt sein können.
- **Teilen** – Der Keller lässt sich über iCloud für eine zweite Person mit eigener Apple-ID freigeben. Einladung in den Einstellungen erzeugen und per Nachricht verschicken; beide sehen danach denselben Bestand, auch beim Abbuchen einer Flasche.
- **Einstellungen** – API-Key und Modellname pro Anbieter, dazu ein eigenes Modell für Siri. Keys lassen sich jederzeit wieder entfernen. Der Anbieter mit hinterlegtem Key ist automatisch aktiv; bei mehreren Keys lässt sich ein bevorzugter wählen. Keys liegen in der Keychain, nie in UserDefaults.

## Voraussetzungen

- Xcode 16 oder neuer (Projekt nutzt synchronisierte Ordner)
- iOS 17 oder neuer
- Ein API-Key bei mindestens einem Anbieter:
  - OpenAI: <https://platform.openai.com/api-keys>
  - Google AI Studio: <https://aistudio.google.com/app/apikey>
  - Anthropic: <https://console.anthropic.com>

## Starten

```bash
open Wyychaellerli.xcodeproj
```

Im Simulator läuft die App ohne Signierung. Für ein echtes Gerät unter „Signing & Capabilities“ das eigene Team wählen.

Build von der Kommandozeile:

```bash
xcodebuild build -project Wyychaellerli.xcodeproj -scheme Wyychaellerli -destination 'generic/platform=iOS Simulator'
```

## Architektur

MVVM mit SwiftUI, Core Data mit CloudKit und `@Observable`.

```
Wyychaellerli/
├── App/            WyychaellerliApp (Einstieg, Environment)
├── Intents/        Siri-Befehl, Kurzbefehl-Anmeldung, Ergebniskarte
├── Models/         Wine und Cellar (Core Data), PairingRequest/PairingResponse, JSON-Schema
├── Persistence/    Core-Data-Stack mit CloudKit, Übernahme der früheren Ablage
├── Services/
│   ├── AIService       Fassade: wählt den Client zum aktiven Anbieter
│   ├── AISettings      Keys (Keychain), Modelle, aktiver Anbieter
│   ├── HTTPTransport   URLSession-Layer, Fehler-Klassifikation
│   ├── PromptBuilder   System- und User-Prompt
│   ├── KeychainStore   Generic-Password-Wrapper
│   ├── LabelScanner/   Vision-OCR, Etikett-Zuschnitt, Apple-Intelligence-, Cloud- und Regel-Zuordnung
│   └── Providers/      OpenAIClient, GeminiClient, AnthropicClient
├── ViewModels/     CellarViewModel, WineFormViewModel, PairingViewModel
├── Views/          Cellar, Advisor, Settings, Components, SplashView
└── Preview Content/ In-Memory-Beispieldaten für Xcode-Previews
Config/Info.plist   Launchscreen-Farbe (wird mit generierter Info.plist zusammengeführt)
Tools/MakeAppIcon.swift  Rendert das App-Icon (hell/dunkel/getönt) in die Assets
```

App-Icon neu erzeugen, z. B. nach Farbänderungen im Script:

```bash
swift Tools/MakeAppIcon.swift
```

Alle drei Anbieter werden per Structured Output auf dasselbe JSON-Schema festgelegt (`RecommendationSchema`), sodass die Antwort immer als `PairingResponse` dekodierbar ist.

### Anbieter-Anbindung

| Anbieter  | Endpoint                                              | Structured Output                          | Standardmodell     |
|-----------|-------------------------------------------------------|--------------------------------------------|--------------------|
| OpenAI    | `POST /v1/chat/completions`                           | `response_format: json_schema` (strict)    | `gpt-5`            |
| Gemini    | `POST /v1beta/models/{model}:generateContent`         | `responseMimeType` + `responseSchema`      | `gemini-2.5-pro`   |
| Anthropic | `POST /v1/messages`                                   | `output_config.format: json_schema`        | `claude-sonnet-5`  |

Der Modellname ist pro Anbieter in den Einstellungen überschreibbar.

### Fehlerbehandlung

`HTTPTransport.classify` ordnet Antworten sprechenden Fehlern zu: ungültiger Key, Guthaben aufgebraucht, Rate-Limit, Anbieter nicht erreichbar, unbekanntes Modell. Der Wein-Berater zeigt Titel, Erklärung und je nach Fall einen Sprung in die Einstellungen oder „Erneut versuchen“.

## Datenschutz

API-Keys werden ausschliesslich in der Keychain des Geräts gespeichert (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) und nur an den jeweiligen Anbieter gesendet. Das Inventar verlässt das Gerät nur als Teil des Prompts an den gewählten Anbieter.
