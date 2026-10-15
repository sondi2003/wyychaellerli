import Foundation

// MARK: - Anfrage

/// Alles, was der Wein-Berater für eine Empfehlung braucht.
struct PairingRequest: Sendable {
    /// Stichwörter zum Essen, z. B. "Raclette" oder "Spaghetti Bolognese".
    let dish: String

    /// Nur nicht-archivierte Weine mit Bestand > 0 gehören hier hinein.
    let inventory: [WineInventoryItem]

    /// Wie viele Vorschläge maximal (Standard: Top 3).
    let maxRecommendations: Int

    init(dish: String, inventory: [WineInventoryItem], maxRecommendations: Int = 3) {
        self.dish = dish.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inventory = inventory
        self.maxRecommendations = maxRecommendations
    }
}

// MARK: - Passung

/// Wie gut ein Wein zum Gericht passt – ehrlich, wie ein Sommelier es sagen würde.
enum FitLevel: String, Codable, Sendable, CaseIterable {
    case excellent
    case good
    case acceptable
    case poor

    var displayName: String {
        switch self {
        case .excellent:  return tr("Perfekt")
        case .good:       return tr("Passt gut")
        case .acceptable: return tr("Geht")
        case .poor:       return tr("Notlösung")
        }
    }

    var symbolName: String {
        switch self {
        case .excellent:  return "star.fill"
        case .good:       return "hand.thumbsup.fill"
        case .acceptable: return "checkmark"
        case .poor:       return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Antwort (strukturiert, von allen drei Anbietern identisch geliefert)

/// Die strukturierte Antwort der KI. Alle drei Provider werden über ein
/// JSON-Schema (siehe `RecommendationSchema`) auf genau dieses Format festgenagelt.
struct PairingResponse: Codable, Sendable, Equatable {
    /// Sortiert nach `rank`, bestes Pairing zuerst. Darf leer sein, wenn nichts passt.
    var recommendations: [PairingRecommendation]

    /// Allgemeiner Hinweis zur Gesamtlogik.
    var generalNote: String

    /// `true`, wenn keine Flasche im Keller mindestens „geht“ – der Sommelier sagt das offen.
    var noGoodMatch: Bool

    /// Was klassisch zu diesem Gericht passen würde – als Kauftipp, wenn der Keller nichts hergibt.
    var shoppingTip: String

    init(recommendations: [PairingRecommendation], generalNote: String, noGoodMatch: Bool = false, shoppingTip: String = "") {
        self.recommendations = recommendations
        self.generalNote = generalNote
        self.noGoodMatch = noGoodMatch
        self.shoppingTip = shoppingTip
    }

    /// Tolerant gegenüber fehlenden Feldern, falls ein Modell das Schema nicht vollständig bedient.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendations = try container.decodeIfPresent([PairingRecommendation].self, forKey: .recommendations) ?? []
        generalNote = try container.decodeIfPresent(String.self, forKey: .generalNote) ?? ""
        noGoodMatch = try container.decodeIfPresent(Bool.self, forKey: .noGoodMatch) ?? false
        shoppingTip = try container.decodeIfPresent(String.self, forKey: .shoppingTip) ?? ""
    }

    /// Convenience: Empfehlungen garantiert nach Rang sortiert.
    var sortedRecommendations: [PairingRecommendation] {
        recommendations.sorted { $0.rank < $1.rank }
    }
}

struct PairingRecommendation: Codable, Sendable, Equatable, Identifiable {
    /// 1 = beste Wahl.
    var rank: Int

    /// Muss exakt dem `name` eines Weins aus dem Inventar entsprechen.
    var wineName: String

    /// Jahrgang des empfohlenen Weins (zur eindeutigen Zuordnung bei Namensdubletten).
    var vintage: Int

    /// Ehrliche Einstufung der Passung.
    var fit: FitLevel

    /// Warum dieser Wein zu dem Gericht passt (2–4 Sätze).
    var reasoning: String

    /// Serviertipp: Temperatur, Dekantieren, Glas …
    var servingTip: String

    var id: String { "\(rank)-\(wineName)-\(vintage)" }

    init(rank: Int, wineName: String, vintage: Int, fit: FitLevel = .good, reasoning: String, servingTip: String) {
        self.rank = rank
        self.wineName = wineName
        self.vintage = vintage
        self.fit = fit
        self.reasoning = reasoning
        self.servingTip = servingTip
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        wineName = try container.decodeIfPresent(String.self, forKey: .wineName) ?? ""
        vintage = try container.decodeIfPresent(Int.self, forKey: .vintage) ?? 0
        fit = (try? container.decodeIfPresent(FitLevel.self, forKey: .fit)) ?? .acceptable
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        servingTip = try container.decodeIfPresent(String.self, forKey: .servingTip) ?? ""
    }
}

// MARK: - JSON-Schema für Structured Output

/// Das JSON-Schema, mit dem alle drei Anbieter auf `PairingResponse` festgelegt werden.
///
/// OpenAI (strict) und Anthropic verlangen `additionalProperties: false` auf jedem Objekt,
/// Gemini lehnt diesen Schlüssel dagegen ab. Deshalb ist das Schema parametrisiert.
enum RecommendationSchema {

    static func jsonSchema(includeAdditionalProperties: Bool) -> [String: Any] {
        var recommendation: [String: Any] = [
            "type": "object",
            "properties": [
                "rank": [
                    "type": "integer",
                    "description": "1 = beste Empfehlung, 2 = zweitbeste, usw. Jeder Rang nur einmal."
                ],
                "wineName": [
                    "type": "string",
                    "description": "Exakter Name des Weins aus dem Inventar (Feld name)."
                ],
                "vintage": [
                    "type": "integer",
                    "description": "Jahrgang des Weins aus dem Inventar (Feld vintage)."
                ],
                "fit": [
                    "type": "string",
                    "enum": FitLevel.allCases.map(\.rawValue),
                    "description": "Ehrliche Passung: excellent, good, acceptable oder poor."
                ],
                "reasoning": [
                    "type": "string",
                    "description": "Konkrete Begründung in der Antwortsprache (2–4 Sätze), warum und wie gut der Wein zum Gericht passt."
                ],
                "servingTip": [
                    "type": "string",
                    "description": "Kurzer Serviertipp in der Antwortsprache (Temperatur, Dekantieren, Glas)."
                ]
            ],
            "required": ["rank", "wineName", "vintage", "fit", "reasoning", "servingTip"]
        ]

        var root: [String: Any] = [
            "type": "object",
            "properties": [
                "recommendations": [
                    "type": "array",
                    "description": "Bis zu drei Empfehlungen aus dem Inventar, nach Rang sortiert. Leer, wenn keine Flasche mindestens acceptable ist.",
                    "items": recommendation
                ],
                "generalNote": [
                    "type": "string",
                    "description": "Allgemeiner Hinweis in der Antwortsprache zur Auswahl (1–3 Sätze)."
                ],
                "noGoodMatch": [
                    "type": "boolean",
                    "description": "true, wenn keine Flasche im Keller mindestens acceptable passt."
                ],
                "shoppingTip": [
                    "type": "string",
                    "description": "Was klassisch zu diesem Gericht passen würde (Rebsorte/Stil/Region), als Kauftipp. Immer ausfüllen."
                ]
            ],
            "required": ["recommendations", "generalNote", "noGoodMatch", "shoppingTip"]
        ]

        if includeAdditionalProperties {
            recommendation["additionalProperties"] = false
            root["additionalProperties"] = false
            // `items` wurde bereits kopiert – neu setzen, damit die Änderung ankommt.
            if var props = root["properties"] as? [String: Any],
               var recs = props["recommendations"] as? [String: Any] {
                recs["items"] = recommendation
                props["recommendations"] = recs
                root["properties"] = props
            }
        }

        return root
    }
}
