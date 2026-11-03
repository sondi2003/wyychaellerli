import SwiftUI
import CoreData

/// Tab 2: Essens-Stichwort eingeben und Top-3-Empfehlung vom aktiven Anbieter holen.
struct AdvisorView: View {

    @Environment(\.openSettings) private var openSettings
    @Environment(PartySession.self) private var party
    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @Environment(LocalAIStatus.self) private var localAI
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var fetchedWines: FetchedResults<Wine>
    @State private var viewModel = PairingViewModel()
    @FocusState private var dishFieldFocused: Bool
    /// Abbuchen mit demselben Ablauf wie in der Kellerliste (Fach, letzte Flasche, Bewerten).
    @State private var consumer = BottleConsumer()
    @State private var isShowingPartyHistory = false
    @State private var isMissingDeviceLock = false

    private var wines: [Wine] { Array(fetchedWines) }

    /// Wer als Erstes gefragt wird: lokal, sonst die externe KI – oder `nil`, wenn keiner da ist.
    private var activeSourceName: String? {
        let local = localAI.primary.map(PairingSource.local)
        let external = settings.activeProvider.map { PairingSource.external($0, model: settings.model(for: $0)) }
        return (settings.prefersExternal ? (external ?? local) : (local ?? external))?.displayName
    }

    /// Nur was wirklich im Keller liegt, geht an die KI.
    private var availableWines: [Wine] {
        wines.filter { !$0.isArchived && $0.quantity > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Solange noch nichts gefragt ist, begrüsst die dunkle Kopfkarte.
                    if showsIntro {
                        BrandHero(
                            title: "Sag mir, was du kochst.",
                            subtitle: "Ich schlage dir bis zu drei passende Weine aus deinem eigenen Keller vor – mit Begründung und Serviertipp.",
                            symbol: "fork.knife.circle.fill"
                        )
                    }
                    dishInputCard
                    requestButton

                    if viewModel.hasLabelMatches {
                        labelMatchSection
                    } else if let outcome = viewModel.labelCheckOutcome {
                        labelCheckNote(outcome)
                    }

                    if viewModel.isLoading {
                        loadingCard
                    } else if let error = viewModel.error {
                        errorCard(error)
                    } else if let response = viewModel.response {
                        resultSection(response)
                    }

                    partyCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wein-Berater")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProviderStatusBadge(settings: settings, local: localAI) { openSettings() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: viewModel.response)
            .bottleConsumerFlow(consumer)
            .navigationDestination(for: Wine.self) { wine in
                WineDetailView(wine: wine)
            }
            .sheet(isPresented: $isShowingPartyHistory) {
                PartyHistoryView()
            }
            .alert("Gerät ohne Sperre", isPresented: $isMissingDeviceLock) {
                Button("Verstanden", role: .cancel) { }
            } message: {
                Text("Der Party-Modus lässt sich nur mit Face ID, Touch ID oder Gerätecode wieder verlassen. Richte in den iPhone-Einstellungen unter „Face ID & Code“ eine Sperre ein.")
            }
        }
    }

    // MARK: Party

    /// Die zweite Antwort auf „Welche Flasche öffnen wir?“: nicht nach dem Essen, sondern
    /// nach Stimmen. Deshalb hier und nicht mehr im Menü der Kellerliste, wo sie zwei
    /// Ebenen tief zwischen Filtern lag.
    private var partyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Gemeinsam abstimmen")
                    .font(.headline)
                    .foregroundStyle(.white)
            } icon: {
                Image(systemName: "party.popper.fill")
                    .foregroundStyle(Brand.rose)
            }
            Text("Die Gäste wählen, welche Flasche heute aufgeht. Das iPhone geht von Hand zu Hand.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    // Ohne Gerätesperre kein Party-Modus – sonst käme man nicht heraus.
                    if PartyLock.isAvailable {
                        party.start()
                    } else {
                        isMissingDeviceLock = true
                    }
                } label: {
                    Label("Party starten", systemImage: "party.popper")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.burgundy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                Button {
                    isShowingPartyHistory = true
                } label: {
                    Label("Historie", systemImage: "trophy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Capsule().strokeBorder(Brand.rose.opacity(0.8), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Brand.rose.opacity(0.7), lineWidth: 1.5)
        )
        .padding(.top, 8)
    }

    // MARK: Eingabe

    private var dishInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Was gibt es zu essen?", systemImage: "fork.knife")
                .font(.headline)

            HStack {
                TextField("z. B. Raclette, Spaghetti Bolognese …", text: $viewModel.dish)
                    .focused($dishFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { Task { await request() } }
                if !viewModel.dish.isEmpty {
                    Button {
                        viewModel.dish = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill).opacity(0.5), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [Brand.rose, Brand.accent], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1.5
                )
            )

            guestsRow

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PairingViewModel.suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            viewModel.dish = suggestion
                            dishFieldFocused = false
                        }
                        .buttonStyle(.brandOutline)
                    }
                }
            }
        }
        .cardStyle()
    }

    /// Personenzahl: optional, aber sie entscheidet, ob eine Flasche reicht.
    private var guestsRow: some View {
        HStack {
            Label("Personen", systemImage: "person.2")
                .font(.subheadline)
            Spacer()
            if let guests = viewModel.guests {
                Stepper(value: Binding(get: { guests }, set: { viewModel.guests = $0 }), in: 1...40) {
                    Text("\(guests)")
                        .font(.body.monospacedDigit().weight(.semibold))
                }
                .fixedSize()
                Button {
                    viewModel.guests = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Entfernen")
            } else {
                Button("Angeben") { viewModel.guests = 2 }
                    .font(.subheadline)
            }
        }
    }

    // MARK: Aktion

    private var requestButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await request() }
            } label: {
                Label("Empfehlung holen", systemImage: "sparkles")
            }
            .buttonStyle(.brand(.filled, large: true))
            .disabled(!viewModel.canRequest(hasInventory: !availableWines.isEmpty))

            hintLine
        }
    }

    /// Eine Zeile unter dem Button: entweder was fehlt, oder was gleich passiert.
    @ViewBuilder
    private var hintLine: some View {
        if let sourceName = activeSourceName {
            if availableWines.isEmpty {
                Text("Im Keller liegt gerade keine Flasche mit Bestand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "\(sourceName) · " + tr("\(availableWines.count) Weine mit Bestand"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Text("Ohne KI wird nur geprüft, ob ein Etikett das Gericht ausdrücklich nennt. Apple Intelligence lässt sich in den Systemeinstellungen einschalten – oder du hinterlegst einen API-Key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Einstellungen öffnen") { openSettings() }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func request(forceAI: Bool = false) async {
        dishFieldFocused = false
        await viewModel.requestRecommendation(
            wines: availableWines,
            settings: settings,
            service: aiService,
            local: localAI,
            forceAI: forceAI
        )
    }

    // MARK: Zustände

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("\(activeSourceName ?? tr("Die KI")) schaut in deinen Keller …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    /// Weder Ergebnis noch Fehler noch Laden – die Seite steht noch am Anfang.
    private var showsIntro: Bool {
        !viewModel.isLoading && viewModel.error == nil && viewModel.response == nil && !viewModel.hasLabelMatches
    }

    private func errorCard(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(error.title, systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if error.suggestsSettings {
                    Button {
                        openSettings()
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    .buttonStyle(.brandOutline)
                }
                Spacer()
                Button {
                    Task { await request() }
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.brandFilled)
                .disabled(!viewModel.canRequest(hasInventory: !availableWines.isEmpty))
            }
        }
        .cardStyle()
    }

    // MARK: Ergebnis

    private func resultSection(_ response: PairingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Empfehlung für „\(viewModel.resultDish)“")
                    .font(.headline)
                Spacer()
                if let source = viewModel.resultSource {
                    Label(source.displayName, systemImage: source.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .help(source.detail)
                }
            }

            if response.recommendations.isEmpty {
                noMatchCard(response)
            } else {
                if !response.generalNote.isEmpty {
                    CalloutBox(kind: response.noGoodMatch ? .warning : .info, text: response.generalNote)
                }
                if response.noGoodMatch, !response.shoppingTip.isEmpty {
                    shoppingTipRow(response.shoppingTip)
                }
            }

            ForEach(response.sortedRecommendations) { recommendation in
                let wine = matchingWine(for: recommendation)
                RecommendationCard(recommendation: recommendation, wine: wine) {
                    if let wine { consumer.consume(wine) }
                }
            }
        }
    }

    // MARK: Rückmeldung des lokalen Abgleichs

    /// Macht sichtbar, dass zuerst ohne KI gesucht wurde – und warum das nichts ergab.
    @ViewBuilder
    private func labelCheckNote(_ outcome: PairingViewModel.LabelCheckOutcome) -> some View {
        if outcome != .matched {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuerst ohne KI gesucht")
                        .font(.subheadline.weight(.semibold))
                    Text(outcome == .nothingStored
                         ? "Bei keiner Flasche sind Speiseempfehlungen vom Etikett erfasst. Beim Scannen werden sie automatisch übernommen, sofern sie auf dem Etikett stehen."
                         : "Kein Etikett nennt „\(viewModel.labelMatchDish)“.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich mit
                // dem Spacer und bricht unnötig um.
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Treffer laut Etikett

    /// Direkte Treffer aus den Etiketten – ohne KI-Anfrage, ohne Kosten.
    private var labelMatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Laut Etikett passend zu „\(viewModel.labelMatchDish)“")
                    .font(.headline)
                Spacer()
                Text("ohne KI")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }

            ForEach(viewModel.labelMatches) { match in
                LabelMatchCard(wine: match.wine, terms: match.terms) {
                    consumer.consume(match.wine)
                }
            }

            if viewModel.response == nil, !viewModel.isLoading, PairingEngine.hasAnySource(settings: settings, local: localAI) {
                Button {
                    Task { await request(forceAI: true) }
                } label: {
                    Label("Zusätzlich die KI fragen", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandOutline)
            }
        }
    }

    /// Ehrliche Absage: keine Flasche im Keller passt – mit Begründung und Kauftipp.
    private func noMatchCard(_ response: PairingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keine passende Flasche im Keller", systemImage: "wineglass")
                .font(.headline)
            Text(verbatim: response.generalNote.isEmpty
                 ? tr("Zu diesem Gericht passt nichts aus deinem aktuellen Bestand wirklich – da bin ich lieber ehrlich.")
                 : response.generalNote)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !response.shoppingTip.isEmpty {
                shoppingTipRow(response.shoppingTip)
            }
        }
        .cardStyle()
    }

    /// Was klassisch passen würde – als Kauftipp fürs nächste Mal.
    private func shoppingTipRow(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cart")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Das würde klassisch passen")
                    .font(.subheadline.weight(.semibold))
                Text(tip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Ordnet eine Empfehlung dem Wein im Keller zu (Name + Jahrgang, Name-Fallback).
    private func matchingWine(for recommendation: PairingRecommendation) -> Wine? {
        let name = recommendation.wineName.lowercased()
        return wines.first { $0.name.lowercased() == name && Int($0.vintage) == recommendation.vintage }
            ?? wines.first { $0.name.lowercased() == name }
    }
}

// MARK: - Karte für Etikett-Treffer

/// Zeigt einen Wein, dessen Etikett das gesuchte Gericht ausdrücklich nennt.
private struct LabelMatchCard: View {

    let wine: Wine
    let terms: [String]
    let onOpenBottle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LabelThumbnail(wine: wine, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    if !wine.producer.isEmpty {
                        Text(wine.producer)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(wine.name)
                        .font(.headline)
                    Text(wine.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // Der Text bekommt den freien Platz zuerst, sonst teilt er ihn sich mit
                // dem Spacer und bricht unnötig um.
                .layoutPriority(1)
                Spacer(minLength: 0)
            }

            // Genau die Begriffe, die auf dem Etikett stehen.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(terms.joined(separator: " · "))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                StockBadge(quantity: Int(wine.quantity))
                Spacer()
                WineActionButtons(wine: wine, onOpenBottle: onOpenBottle)
            }
        }
        .cardStyle()
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.green.opacity(0.45), lineWidth: 1.5)
        }
    }
}

// MARK: - Statusanzeige in der Toolbar

/// Zeigt, wer gerade antwortet – Apple lokal, die externe KI oder keiner. Tippen führt in die Einstellungen.
struct ProviderStatusBadge: View {
    let settings: AISettings
    let local: LocalAIStatus
    let onTap: () -> Void

    private var source: PairingSource? {
        let localSource = local.primary.map(PairingSource.local)
        let external = settings.activeProvider.map { PairingSource.external($0, model: settings.model(for: $0)) }
        return settings.prefersExternal ? (external ?? localSource) : (localSource ?? external)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let source {
                    Image(systemName: source.symbolName)
                    Text(source.displayName == local.primary?.displayName ? (local.primary?.shortName ?? source.displayName) : source.displayName)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Keine KI")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 4)
        }
        .tint(source == nil ? .orange : .accentColor)
        .accessibilityLabel(source.map { tr("Aktive Quelle: \($0.displayName)") } ?? tr("Keine KI eingerichtet"))
    }
}

#Preview {
    AdvisorView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(PartySession())
        .environment(AISettings(defaults: PreviewData.defaults))
}
