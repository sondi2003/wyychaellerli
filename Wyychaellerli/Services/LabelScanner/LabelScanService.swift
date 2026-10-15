import Foundation
import OSLog

/// Snapshot der Cloud-Zugangsdaten, damit der Service nicht am Main Actor hängt.
struct CloudCredentials: Sendable {
    let provider: AIProvider
    let apiKey: String
    let model: String
}

/// Orchestriert die Etikett-Erkennung:
/// 1. Texterkennung auf dem Gerät (Vision)
/// 2. Zuschnitt des Vorderseiten-Fotos aufs Etikett
/// 3. Zuordnung zu Feldern – Apple Intelligence, sonst aktiver Cloud-Anbieter, sonst Regeln
struct LabelScanService: Sendable {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "LabelScan")
    private let aiService: AIService

    init(aiService: AIService) {
        self.aiService = aiService
    }

    /// Erkennt Text in den Bildern, schneidet die Vorderseite zu und ordnet die Felder zu.
    /// - Parameter cloud: Zugangsdaten des aktiven Anbieters oder `nil`, wenn keiner eingerichtet ist.
    /// - Parameters:
    ///   - frontExtras, backExtras: Weitere Ansichten derselben Seite (von links, von rechts).
    ///     Ihr Text wird mit dem der Hauptansicht zusammengeführt; Foto und Zuschnitt
    ///     kommen immer von der Hauptansicht.
    func scan(
        front: ScanImage?, frontExtras: [ScanImage] = [],
        back: ScanImage?, backExtras: [ScanImage] = [],
        cloud: CloudCredentials?
    ) async throws -> LabelScanResult {
        var sections: [(title: String, lines: [RecognizedLine])] = []
        var labelImageData: Data?
        var backLabelImageData: Data?

        if let front {
            var lines = try await LabelTextRecognizer.recognizeLines(in: front)
            if let crop = await LabelImageCropper.cropLabel(from: front, textLines: lines) {
                labelImageData = crop.jpegData
                Self.logger.info("Etikett vorne: \(crop.jpegData.count) Bytes, Zuschnitt \(crop.strategy.rawValue), Drehung \(crop.rotation)°")
                lines = await Self.rereadingLabel(lines, crop: crop, side: "vorne")
            }
            lines = await Self.merging(lines, with: frontExtras, side: "vorne")
            sections.append(("Vorderseite", lines))
        }
        if let back {
            var lines = try await LabelTextRecognizer.recognizeLines(in: back)
            if let crop = await LabelImageCropper.cropLabel(from: back, textLines: lines) {
                backLabelImageData = crop.jpegData
                Self.logger.info("Etikett hinten: \(crop.jpegData.count) Bytes, Zuschnitt \(crop.strategy.rawValue), Drehung \(crop.rotation)°")
                lines = await Self.rereadingLabel(lines, crop: crop, side: "hinten")
            }
            lines = await Self.merging(lines, with: backExtras, side: "hinten")
            sections.append(("Rückseite", lines))
        }

        let text = LabelTextRecognizer.combinedText(sections)
        guard !text.isEmpty else { throw LabelScanError.noTextFound }
        Self.logger.info("OCR: \(text.count) Zeichen erkannt")

        var (extraction, source) = await structure(text: text, cloud: cloud)
        // Speiseempfehlungen nur übernehmen, wenn sie im Etikett-Text belegt sind.
        extraction = Self.verifyingFoodPairings(extraction, against: text)
        // Die Modelle übernehmen den Rückseitentext gern in der Originalsprache.
        if !extraction.notes.isEmpty {
            extraction.notes = await LabelNotesTranslator.localized(
                extraction.notes,
                aiService: aiService,
                cloud: cloud
            )
        }
        guard extraction.hasContent else { throw LabelScanError.nothingRecognized(text) }
        Self.logger.info("Zuordnung via \(source.displayName)")
        return LabelScanResult(
            extraction: extraction,
            recognizedText: text,
            source: source,
            labelImageData: labelImageData,
            backLabelImageData: backLabelImageData
        )
    }

    /// Zweiter Durchgang auf dem Zuschnitt.
    ///
    /// Im ersten Durchgang ist das Etikett nur ein Ausschnitt des ganzen Fotos – auf
    /// einer schmalen Flasche ein kleiner. Der Zuschnitt aus dem vollen Foto hat für
    /// dieselben Buchstaben ein Vielfaches an Pixeln. Gelesen wird beides; es gewinnt,
    /// was mehr sichere Zeichen liefert – so kann der zweite Durchgang nie schaden.
    private static func rereadingLabel(_ first: [RecognizedLine], crop: LabelCropResult, side: String) async -> [RecognizedLine] {
        guard let ocrImage = crop.ocrImage else { return first }
        guard let second = try? await LabelTextRecognizer.recognizeLines(in: ScanImage(cgImage: ocrImage, orientation: .up)) else {
            return first
        }
        let firstScore = LabelTextRecognizer.score(of: first)
        let secondScore = LabelTextRecognizer.score(of: second)
        logger.info("Zweites Lesen \(side): ganzes Foto \(Int(firstScore)), Zuschnitt \(Int(secondScore)) Punkte")
        return secondScore > firstScore ? second : first
    }

    /// Text weiterer Ansichten dazunehmen – nur Zeilen, die noch fehlen.
    ///
    /// Auf einer schmalen Flasche läuft die Schrift um die Rundung; die Kamera sieht nicht
    /// um die Ecke. Von links und rechts nachfotografiert, ergibt die Summe das ganze
    /// Etikett. Doppelte Zeilen (dieselbe Zeile aus zwei Winkeln) fallen weg.
    private static func merging(_ lines: [RecognizedLine], with extras: [ScanImage], side: String) async -> [RecognizedLine] {
        guard !extras.isEmpty else { return lines }
        var merged = lines
        var seen = Set(lines.map { Self.lineKey($0.text) })
        var added = 0
        for extra in extras {
            guard let extraLines = try? await LabelTextRecognizer.recognizeLines(in: extra) else { continue }
            for line in extraLines where seen.insert(Self.lineKey(line.text)).inserted {
                merged.append(line)
                added += 1
            }
        }
        logger.info("Weitere Ansichten \(side): \(extras.count) Fotos, \(added) neue Zeilen")
        return merged
    }

    /// Gleiche Zeile aus zwei Winkeln: Abstände, Satzzeichen, Gross/Klein und Akzente
    /// dürfen abweichen. Bleibt nach dem Abstreifen zu wenig, zählt die Zeile für sich.
    private static func lineKey(_ text: String) -> String {
        let key = normalized(text)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return key.count >= 3 ? key : UUID().uuidString
    }

    /// Wählt die beste verfügbare Zuordnung und fällt bei Fehlern eine Stufe zurück.
    private func structure(text: String, cloud: CloudCredentials?) async -> (WineLabelExtraction, LabelExtractionSource) {
        let heuristic = HeuristicLabelParser.parse(recognizedText: text)

        // 1. Apple Intelligence auf dem Gerät
        #if canImport(FoundationModels)
        // Das Modell auf dem Gerät antwortet nur auf Deutsch; für Serbisch geht es gleich zur Cloud.
        if #available(iOS 26.0, *), AppLanguage.current.isGerman, OnDeviceLabelParser.isAvailable {
            do {
                let extraction = try await OnDeviceLabelParser.parse(recognizedText: text)
                if extraction.hasContent {
                    return (merge(extraction, with: heuristic), .onDevice)
                }
                Self.logger.warning("Apple Intelligence lieferte keine Felder")
            } catch {
                Self.logger.error("Apple Intelligence fehlgeschlagen: \(String(describing: error))")
            }
        }
        #endif

        // 2. Aktiver Cloud-Anbieter (nur Text, kein Foto)
        if let cloud {
            do {
                let extraction = try await aiService.extractLabel(
                    recognizedText: text,
                    provider: cloud.provider,
                    apiKey: cloud.apiKey,
                    model: cloud.model
                )
                if extraction.hasContent {
                    return (merge(extraction, with: heuristic), .cloud(cloud.provider))
                }
                Self.logger.warning("\(cloud.provider.shortName) lieferte keine Felder")
            } catch {
                Self.logger.error("\(cloud.provider.shortName) fehlgeschlagen: \(error.localizedDescription)")
            }
        }

        // 3. Regeln ohne KI
        return (heuristic, .heuristic)
    }

    /// Verwirft Speiseempfehlungen, für die es im erkannten Text keinen Beleg gibt.
    ///
    /// Ein Modell neigt dazu, aus Rebsorte und Region eine Empfehlung abzuleiten. Die App
    /// behauptet aber „laut Etikett“, also muss das Etikett es auch hergeben. Als Beleg
    /// dient der wörtlich kopierte Abschnitt; er muss sich im erkannten Text wiederfinden.
    static func verifyingFoodPairings(_ extraction: WineLabelExtraction, against recognizedText: String) -> WineLabelExtraction {
        guard !extraction.foodPairings.isEmpty else { return extraction }
        var checked = extraction
        guard isSupported(extraction.foodPairingSource, by: recognizedText) else {
            Self.logger.info("Speiseempfehlung ohne Beleg im Etikett-Text verworfen: \(extraction.foodPairings.joined(separator: ", "))")
            checked.foodPairings = []
            checked.foodPairingSource = ""
            return checked
        }
        return checked
    }

    /// Der Beleg gilt, wenn genügend seiner Wörter im erkannten Text vorkommen.
    /// Eine exakte Übereinstimmung wäre zu streng, weil die Texterkennung Buchstaben verdreht.
    private static func isSupported(_ source: String, by recognizedText: String) -> Bool {
        let haystack = normalized(recognizedText)
        let words = normalized(source)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard words.count >= 2 else { return false }
        let found = words.filter { haystack.contains($0) }.count
        return Double(found) / Double(words.count) >= 0.6
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
    }

    /// Füllt Lücken der KI-Zuordnung mit den regelbasierten Treffern (z. B. Jahrgang, Alkohol).
    private func merge(_ primary: WineLabelExtraction, with fallback: WineLabelExtraction) -> WineLabelExtraction {
        var merged = primary
        if merged.vintage == 0 { merged.vintage = fallback.vintage }
        if merged.alcoholPercent == 0 { merged.alcoholPercent = fallback.alcoholPercent }
        if merged.wineType == nil, fallback.wineType != nil { merged.type = fallback.type }
        if merged.grape.isEmpty { merged.grape = fallback.grape }
        if merged.region.isEmpty { merged.region = fallback.region }
        if merged.country.isEmpty { merged.country = fallback.country }
        if merged.foodPairings.isEmpty { merged.foodPairings = fallback.foodPairings }
        if merged.foodPairingSource.isEmpty { merged.foodPairingSource = fallback.foodPairingSource }
        return merged
    }
}

enum LabelScanError: LocalizedError {
    case noTextFound
    case nothingRecognized(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return tr("Auf den Fotos wurde kein Text erkannt. Bitte das Etikett näher und bei gutem Licht fotografieren.")
        case .nothingRecognized:
            return tr("Der Text konnte keinem Feld zugeordnet werden. Du kannst die Angaben manuell eintragen.")
        }
    }
}
