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
| gtin | String | Strichcode, falls bekannt |
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

Zusätzlich **Queryable**: `CatalogWine.searchTokens`, `WineSubmission.status`,
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
6. **Mitteilung**: CloudKit-Abo (`CKQuerySubscription`) des Nutzers auf seine eigenen
   Vorschläge, ausgelöst bei Statuswechsel. Richard hat ein Abo auf neue Vorschläge.
   Kein eigener Server nötig.

## Abgleich

1. Exakter Schlüssel (`wine_<hash>`, später `ean_<gtin>`).
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
   einmal öffnen und unter Meine Vorschläge die Kennung ablesen – in Production kann sie
   anders sein als in Development.
3. **Konsole → Production**: Records → Public Database → `CatalogAdmin` → + →
   Record Name `admins`, `userRecordNames` = Kennung aus Schritt 2.
4. **Production → Users**: Index `recordName` (Queryable) gibt es dort erst nach dem
   Deploy; den eigenen Benutzer öffnen → Security Roles → `Admin` anhaken → Save.
5. **App Store Connect → App-Datenschutz**: neu „Sonstige Nutzerinhalte“ und
   „Fotos oder Videos“, mit dem Nutzer verknüpft, kein Tracking, Zweck App-Funktionalität.
   Nötig vor der Einreichung im App Store, für TestFlight intern nicht.
