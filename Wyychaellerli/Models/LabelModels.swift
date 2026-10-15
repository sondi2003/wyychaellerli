import Foundation

// MARK: - Ergebnis der Etikett-Erkennung

/// Aus dem Etikett extrahierte Felder. Leere Strings bzw. 0 bedeuten „nicht erkannt“.
struct WineLabelExtraction: Codable, Sendable, Equatable {
    var name: String = ""
    var producer: String = ""
    var vintage: Int = 0
    var grape: String = ""
    var region: String = ""
    var country: String = ""
    /// Rohwert: "red", "white", "sparkling", "rose", "mulled" oder "unknown".
    var type: String = "unknown"
    var alcoholPercent: Double = 0
    var notes: String = ""
    /// Speiseempfehlungen vom Etikett, auf Deutsch übersetzt.
    var foodPairings: [String] = []
    /// Empfohlene Trinkjahre. 0 heisst „nicht bestimmbar“.
    var drinkFrom: Int = 0
    var drinkTo: Int = 0
    /// `true`, wenn die Spanne wirklich auf dem Etikett stand, `false` bei einer Schätzung.
    var drinkWindowFromLabel: Bool = false
    /// Der wörtliche Textabschnitt vom Etikett, auf dem die Empfehlung beruht.
    /// Dient als Beleg: Lässt er sich im erkannten Text nicht wiederfinden, werden
    /// die Empfehlungen verworfen.
    var foodPairingSource: String = ""

    /// Typ als App-Enum, falls erkannt.
    var wineType: WineType? {
        WineType(rawValue: type.lowercased())
    }

    /// `true`, wenn wenigstens ein Kernfeld gefüllt ist.
    var hasContent: Bool {
        !name.isEmpty || !producer.isEmpty || vintage > 0 || !grape.isEmpty || !region.isEmpty || !country.isEmpty
    }
}

/// Womit die Zuordnung der Felder gemacht wurde – für die Anzeige in der UI.
enum LabelExtractionSource: Sendable, Equatable {
    case onDevice
    case cloud(AIProvider)
    case heuristic

    var displayName: String {
        switch self {
        case .onDevice:            return tr("Apple Intelligence (auf dem Gerät)")
        case .cloud(let provider): return provider.shortName
        case .heuristic:           return tr("einfache Erkennung ohne KI")
        }
    }
}

/// Erkanntes Etikett samt Rohtext und Quelle – wird ans Formular übergeben.
struct LabelScanResult: Sendable, Identifiable, Equatable {
    let id = UUID()
    let extraction: WineLabelExtraction
    let recognizedText: String
    let source: LabelExtractionSource
    /// Aufs Etikett zugeschnittenes Foto der Vorderseite (JPEG), falls vorhanden.
    let labelImageData: Data?
    /// Dasselbe für die Rückseite – dort steht der Text, den man später nachlesen will.
    let backLabelImageData: Data?
}

// MARK: - JSON-Schema für die Cloud-Zuordnung

/// Schema, auf das OpenAI/Gemini/Anthropic bei der Etikett-Zuordnung festgelegt werden.
/// Alle Felder sind Pflicht (strict-kompatibel); „unbekannt“ = leerer String bzw. 0.
enum LabelSchema {

    static func jsonSchema(includeAdditionalProperties: Bool, language: AppLanguage = .current) -> [String: Any] {
        let target = language.promptName
        let targetAccusative = language.promptTarget
        var schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Name des Weins oder der Cuvée ohne Produzent, z. B. \"La Pinède\". Leer, wenn unbekannt."],
                "producer": ["type": "string", "description": "Produzent, Weingut, Domaine oder Château. Leer, wenn unbekannt."],
                "vintage": ["type": "integer", "description": "Jahrgang als vierstellige Zahl, nur wenn er wörtlich im Text steht. Nie raten, nie das aktuelle Jahr einsetzen, Postleitzahlen in Adressen nicht verwechseln. 0, wenn keiner auf dem Etikett steht."],
                "grape": ["type": "string", "description": "Rebsorten, kommagetrennt, in Originalschreibweise. Leer, wenn unbekannt."],
                "region": ["type": "string", "description": "Region oder Appellation, z. B. \"Collioure\". Leer, wenn unbekannt."],
                "country": ["type": "string", "description": "Herkunftsland auf \(target), z. B. \(language.promptCountryExamples.components(separatedBy: ", ")[0].replacingOccurrences(of: "\"", with: "\\\"")). Auch ableiten, wenn nur die Appellation genannt ist. Leer, wenn unklar."],
                "type": ["type": "string", "enum": ["red", "white", "sparkling", "rose", "mulled", "unknown"], "description": "Weintyp. \"mulled\" für Glühwein und verwandte Winter-Heissgetränke."],
                "alcoholPercent": ["type": "number", "description": "Alkoholgehalt in Volumenprozent, 0 wenn unbekannt."],
                "notes": ["type": "string", "description": "Kurze Notiz zu Terroir, Vinifikation und Ausbau (max. 2 Sätze), zwingend auf \(target) – fremdsprachigen Etikett-Text übersetzen, nicht kopieren. Leer, wenn nichts dazu auf dem Etikett steht."],
                "foodPairings": [
                    "type": "array",
                    "description": "Speiseempfehlungen, die auf dem Etikett stehen, ins \(targetAccusative) übersetzt. Je Eintrag ein kurzer Begriff. Leeres Array, wenn das Etikett nichts dazu sagt.",
                    "items": ["type": "string"]
                ],
                "drinkFrom": ["type": "integer", "description": "Erstes empfohlenes Trinkjahr als vierstellige Zahl, 0 wenn nicht bestimmbar."],
                "drinkTo": ["type": "integer", "description": "Letztes empfohlenes Trinkjahr als vierstellige Zahl, 0 wenn nicht bestimmbar."],
                "drinkWindowFromLabel": ["type": "boolean", "description": "true nur, wenn die Trinkreife ausdrücklich auf dem Etikett steht. Bei einer Einschätzung aus Rebsorte, Region und Jahrgang false."],
                "foodPairingSource": [
                    "type": "string",
                    "description": "Der wörtlich aus dem erkannten Text kopierte Abschnitt, auf dem foodPairings beruht – unübersetzt, genau wie im Text. Leer, wenn es keine Speiseempfehlung gibt."
                ]
            ],
            "required": ["name", "producer", "vintage", "grape", "region", "country", "type", "alcoholPercent", "notes", "foodPairings", "foodPairingSource", "drinkFrom", "drinkTo", "drinkWindowFromLabel"]
        ]
        if includeAdditionalProperties {
            schema["additionalProperties"] = false
        }
        return schema
    }
}
