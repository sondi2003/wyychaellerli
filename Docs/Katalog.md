# Gemeinsamer Weinkatalog

Stand 2.11.2026. Entwurf und Bauplan, gemeinsam mit Richard festgelegt.

## Idee

Ein Katalog geprüfter Weine, den alle Käufer der App beim Erfassen nutzen. Er wächst
durch die Nutzer: Was nicht im Katalog steht, kann ein Nutzer vorschlagen. Richard prüft
jeden Vorschlag in einem Admin-Bereich, korrigiert bei Bedarf und nimmt ihn auf oder
lehnt ab. Der Nutzer bekommt den Entscheid als Mitteilung.

Externe Datenquellen (APIs) können den Katalog später zusätzlich füllen – über n8n, nie
aus der App. Am 2.11.2026 geprüft und vorerst verworfen:

- **Vinou** (öffentlich, ohne Schlüssel): rund 6800 Weine, 82 % aus Deutschland, 6 aus
  der Schweiz. Von 14 Weinen aus Richards Keller war **keiner** zu finden. Die Suche nimmt
  jedes Wort einzeln („Sasso al Vento“ ergibt über 5000 Treffer). Keine Trinkreife.
- **grapeminds** (Gratis-Tarif 250 Anfragen/Monat): Die AGB verbieten die Weitergabe und
  gelten nur für Deutschland; dauerhaftes Speichern braucht laut eigener Schnittstelle
  eine kostenpflichtige Lizenz je Wein (`/licence/{wine_id}`). Kein Strichcode, kein Bild.

Die Tür bleibt offen: Der Katalog kennt eine Herkunft je Eintrag (`source`, `sourceID`),
und ein Import überschreibt nie, was Richard bearbeitet hat (`adminEdited`).

## Wo die Daten liegen

**Öffentliche Datenbank** des bestehenden Containers `iCloud.com.sondinetwork.weinkeller.app`.
Der eigene Keller (private und geteilte Datenbank, Core Data) bleibt unberührt; es gibt
**keine** Änderung am Core-Data-Modell. Der Katalog wird nicht gespiegelt, die App fragt
gezielt nach einzelnen Weinen.

### `CatalogWine` – der geprüfte Katalog

| Feld | Typ | Bemerkung |
|---|---|---|
| recordName | – | `ean_<gtin>` oder `wine_<md5(produzent_name_jahrgang)>`, normalisiert |
| name, producer, grape, region, country, typeRaw | String | wie am Wein in der App |
| vintage | Int64 | 0 = unbekannt |
| alcoholPercent | Double | 0 = unbekannt |
| sweetness, bottleSize | Double | für spätere Quellen, 0 = unbekannt |
| barrique, bio, vegan | Int64 | 0/1 |
| gtins | List<String> | Strichcodes (EAN-13/8) dieses Weins – **Queryable**. Suchmerkmal, kein Schlüssel: Derselbe Code kann über mehrere Jahrgänge gleich bleiben |
| foodPairings | List<String> | Speisen, deutsch (seit 7.11.2026), aus dem Import (Quellfeld `style.food`); kein Index nötig. Vor dem ersten Produktionslauf des Imports „Deploy Schema Changes“ |
| searchTokens | List<String> | normierte Wörter aus Produzent und Name – **Queryable** |
| source | String | `nutzer` / `admin` / später z. B. `vinou` |
| sourceID | String | Kennung bei der Quelle |
| adminEdited | Int64 | 1 = von Richard bearbeitet, ein Import überschreibt nicht |
| image | Asset | Etikett aus dem Vorschlag |

Kein Feld für Trinkreife: Sie bleibt, wie sie ist (vom Etikett oder von der KI geschätzt).

### `WineSubmission` – Vorschläge

Dieselben Stammdaten (name, producer, vintage, grape, region, country, typeRaw,
alcoholPercent) plus:

| Feld | Typ | Bemerkung |
|---|---|---|
| labelImage | Asset | zugeschnittenes Vorderseiten-Etikett |
| catalogKey | String | derselbe Schlüssel wie oben – fasst gleiche Vorschläge zusammen; **Queryable** |
| wineUUID | String | Kennung des Weins im Keller des Nutzers, nur für die Statusanzeige |
| barcode | String | Strichcode des vorgeschlagenen Weins; nur gesetzt, wenn bekannt |
| status | String | `pending` / `accepted` / `rejected` – **Queryable** |
| appVersion | String | zur Fehlersuche |

**Nie** übertragen: Notizen, Bewertungen, Bestand, Regal, Rückseite.

### `CatalogAdmin` – wer Admin ist

Ein einziger Datensatz `admins` mit dem Feld `userRecordNames` (List<String>). Die App
zeigt den Admin-Bereich nur, wenn die eigene Kennung darin steht. **Das ist nur die
Anzeige** – geschützt wird über die Rolle in der Konsole.

## Rechte (Security Roles in der CloudKit-Konsole)

| Rolle | CatalogWine | WineSubmission | CatalogAdmin |
|---|---|---|---|
| World | Read | – | Read |
| Authenticated | Read | Create | Read |
| Creator | – | Read | – |
| Admin (nur Richard) | Create, Read, Write | Create, Read, Write | Create, Read, Write |

Zusätzlich **Queryable**: `CatalogWine.searchTokens`, `CatalogWine.gtins`, `WineSubmission.status`,
`WineSubmission.catalogKey`, `WineSubmission.createdUserRecordName` (Systemfeld).

## Ablauf in der App

1. **Scan**: Nach dem Lesen fragt die App den Katalog. Treffer → leere Felder werden
   ergänzt, nie überschrieben, und das Formular sagt „Im Katalog gefunden“.
2. **Sichern**: Ist „Neue Weine vorschlagen“ eingeschaltet und der Wein nicht im Katalog,
   geht er als Vorschlag weg.
3. **Bestehender Keller**: Einstellungen → Gemeinsamer Katalog → „Keller abgleichen“.
   Zeigt, was fehlt; der Nutzer wählt aus, was er schickt.
4. **Detailseite**: Karte mit dem Katalog-Status und „Zur Prüfung senden“.
5. **Admin**: Einstellungen → „Vorschläge prüfen“. Gleiche Vorschläge erscheinen
   zusammengefasst. Felder anpassen, aufnehmen oder ablehnen.
   Einstellungen → „Katalog verwalten“: ganzen Katalog durchsuchen und filtern
   (Weinart, Land, Herkunft, lückenhaft), Einträge korrigieren, Etikett tauschen, löschen.
6. **Mitteilung**: CloudKit-Abo (`CKQuerySubscription`) des Nutzers auf seine eigenen
   Vorschläge, ausgelöst bei Statuswechsel. Richard hat ein Abo auf neue Vorschläge.
   Kein eigener Server nötig.

## Abgleich

0. **Strichcode** (seit 3.11.2026), falls der Scan einen gelesen hat: `gtins CONTAINS`. Der
   **Jahrgang entscheidet**: Ist er bekannt, zählt nur der gleiche (ein Eintrag ohne Jahrgang
   springt ein); ist er unbekannt, gilt nur ein eindeutiger Treffer. Ein neuer Jahrgang
   findet den alten Eintrag also nicht. Scheitert die Abfrage, geht es mit dem Namen weiter.
1. Exakter Schlüssel (`wine_<hash>`; `ean_<gtin>` nur für einen späteren Import, die App
   übergibt nie einen Strichcode).
2. Sonst Kandidaten über das längste Wort von Produzent oder Name (`searchTokens CONTAINS`),
   dann auf dem Gerät mit der Regel aus `DuplicateFinder` (Jahrgang gleich, Name ≥ 0,85,
   Produzent ≥ 0,6).

## Bauplan

1. ~~APIs prüfen~~ (erledigt, siehe oben)
2. App-Code: Dienst, Abgleich, Vorschläge, Admin, Mitteilungen
3. CloudKit-Konsole, Development: Datensatztypen entstehen beim ersten Speichern aus der
   DEV-App auf dem iPhone; danach Indizes, Rollen, Admin-Datensatz von Hand
4. Test auf zwei Geräten (Richard als Admin, zweite Apple-ID als Nutzer)
5. Deploy Schema Changes nach Production, Admin-Datensatz und Rolle dort nochmals
   anlegen (Datensätze und Rollenzuweisungen wandern nicht mit), dann TestFlight
6. Datenschutzerklärung und App-Store-Angaben anpassen („Nutzerinhalte“)
7. Später: Import aus weiteren Quellen über n8n mit Server-Schlüssel

## Schritt für Schritt: Einrichtung in der CloudKit-Konsole (Development)

Voraussetzung: die DEV-App aus Xcode auf dem iPhone, dort bei iCloud angemeldet. Im
Simulator geht es nicht (kein iCloud-Konto).

1. **Kennung holen**: App → Einstellungen → Gemeinsamer Katalog → Meine Vorschläge.
   Unten steht „Deine Katalog-Kennung“ (beginnt mit `_`). Kopieren.
2. **Ersten Vorschlag senden**: einen Wein öffnen → Karte „Gemeinsamer Katalog“ →
   „Zur Prüfung senden“. Damit legt CloudKit den Typ `WineSubmission` in Development
   selbst an.
3. **Konsole öffnen**: icloud.developer.apple.com → CloudKit Console → CloudKit Database →
   Container `iCloud.com.sondinetwork.weinkeller.app` → oben **Development**.
4. **Datensatztypen anlegen** (Schema → Record Types → +):
   - `CatalogWine` mit name, producer, grape, region, country, typeRaw, source, sourceID
     (String), vintage, adminEdited (Int64), alcoholPercent (Double), searchTokens
     (String List), image (Asset).
   - `CatalogAdmin` mit userRecordNames (String List).
5. **Indizes** (Schema → Indexes): `CatalogWine.searchTokens` und `recordName` Queryable;
   `WineSubmission.status`, `catalogKey`, `createdUserRecordName` und `recordName` Queryable; `CatalogAdmin.recordName` Queryable (sonst zeigt die Konsole keine Datensätze).
6. **Rollen** (Schema → Security Roles): neue Rolle `Admin` mit Create, Read, Write auf allen
   drei Typen. World, Authenticated und Creator wie in der Tabelle oben.
7. **Admin-Datensatz** (Records → Public Database → Typ `CatalogAdmin` → +): Record Name
   `admins`, `userRecordNames` = die Kennung aus Schritt 1.
8. **Rolle zuweisen**: den eigenen Benutzer-Datensatz (Typ `Users`, Name = Kennung) öffnen
   und ihm die Rolle `Admin` geben.
9. App neu starten → in den Einstellungen erscheint „Vorschläge prüfen“.

## Schritt für Schritt: Production und TestFlight

Records wandern nie von Development nach Production. Der Katalog beginnt dort leer;
Cicero aus dem Test ist nur in Development.

1. **Deploy Schema Changes**: Konsole → Development → links „Deploy Schema Changes…“.
   Die Liste zeigt die neuen Typen `CatalogWine`, `CatalogAdmin`, `WineSubmission`, ihre
   Indizes und die Rollen (auch `Admin`). `CD_…` sollte nicht dabei sein. Bestätigen.
2. **Build hochladen** (TestFlight, Production-Umgebung). Danach die TestFlight-App
   einmal öffnen, damit der Benutzer-Datensatz in Production entsteht. Die Kennung ist
   dieselbe wie in Development (am 2.11.2026 geprüft).
3. **Konsole → Production**: Records → Public Database → `CatalogAdmin` → + →
   Record Name `admins`, `userRecordNames` = Kennung aus Schritt 2.
4. **Production → Users**: Index `recordName` (Queryable) gibt es dort erst nach dem
   Deploy; den eigenen Benutzer öffnen → Security Roles → `Admin` anhaken → Save.
5. **App Store Connect → App-Datenschutz**: neu „Sonstige Nutzerinhalte“ und
   „Fotos oder Videos“, mit dem Nutzer verknüpft, kein Tracking, Zweck App-Funktionalität.
   Nötig vor der Einreichung im App Store, für TestFlight intern nicht.

## Strichcode (seit 3.11.2026)

- **Lesen**: `BarcodeReader` (Vision, `VNDetectBarcodesRequest`, EAN-13 und EAN-8) liest den
  Code aus denselben Fotos wie den Text, Rückseite zuerst. Gespeichert wird nur, was die
  Prüfziffer besteht (`Barcode.normalized`); UPC-A wird zum EAN-13 mit führender Null.
- **Felder**: `Wine.barcode` (Core Data, Standard leer), `CatalogWine.gtins` (Liste),
  `WineSubmission.barcode`.
- **Ergänzen geht nur über die Prüfung.** Fehlt einem bestehenden Katalogeintrag der
  Strichcode, schickt die App eine **Ergänzung** (Vorschlag mit den Angaben des Eintrags,
  `catalogKey` = dessen Schlüssel, ohne Etikett). Der Admin sieht „Bringt nur einen neuen
  Strichcode mit“ und nimmt auf; die Codes werden **zusammengeführt**, nichts geht
  verloren. Direkt eintragen darf ein Nutzer nichts – schreiben kann nur der Admin. Ohne
  Prüfung ginge es erst mit einem Server (n8n mit Schlüssel).
- **Konsole, Development** (Felder entstehen beim ersten Speichern von selbst, die Indizes
  nicht): Schema → Indexes → `CatalogWine` → `gtins` **Queryable** hinzufügen. Ohne den
  Index scheitert die Abfrage `gtins CONTAINS`; die App fällt dann leise auf den Namen
  zurück.
- **Konsole, Production**: **Deploy Schema Changes** überträgt die Felder `gtins` und
  `barcode` samt Index (und `CD_barcode` am Wein, siehe AGENTS.md). Vor dem nächsten
  TestFlight-Build. Ohne das scheitert in Production das Speichern von Vorschlägen mit
  Strichcode; Vorschläge ohne Strichcode setzen das Feld gar nicht und gehen weiter durch.

## Wenn in Production Vorschläge nicht ankommen

Bild vom 3.11.2026 (TestFlight, zwei Nutzer): Der zweite Nutzer sieht „Wartet auf Prüfung“, beim
Admin erscheint der Vorschlag nicht; die eigenen Vorschläge des Admins erscheinen, aber
Aufnehmen speichert nichts, und der Vorschlag taucht später wieder auf.

**Ursache: die Rolle „Admin“ wirkt in Production nicht.** Ohne sie kann der Admin nur seine
**eigenen** Datensätze lesen und nirgends schreiben. Prüfen, in dieser Reihenfolge:

1. App → Einstellungen → Gemeinsamer Katalog → **Admin-Rechte prüfen** (ab Build 17). Meldet
   „fehlt die Berechtigung“, ist es das.
2. Konsole → **Production** → Schema → Security Roles → `Admin`: Create, Read, Write auf
   `CatalogWine`, `WineSubmission` und `CatalogAdmin`?
3. Konsole → Production → Data → Public Database → Typ **Users** → den eigenen Datensatz
   (Name = Kennung aus „Meine Vorschläge“) öffnen → Rolle `Admin` angehakt? **Speichern**
   und danach den Datensatz erneut öffnen, ob der Haken geblieben ist.
4. Konsole → Production → **Logs**: Fehler `PERMISSION_FAILURE` bei `modifyRecords` bestätigen es.
5. App ganz beenden und neu starten.

Die hängenden Vorschläge bleiben liegen und lassen sich danach normal aufnehmen: Beim
Aufnehmen wurde nichts geschrieben, es gibt keine Doppeleinträge.
