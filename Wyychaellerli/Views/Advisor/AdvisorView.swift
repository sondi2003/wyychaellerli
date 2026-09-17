import SwiftUI
import CoreData

/// Tab 2: Essens-Stichwort eingeben und Top-3-Empfehlung vom aktiven Anbieter holen.
struct AdvisorView: View {

    @Binding var selectedTab: AppTab

    @Environment(AISettings.self) private var settings
    @Environment(\.aiService) private var aiService
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var fetchedWines: FetchedResults<Wine>
    @State private var viewModel = PairingViewModel()
    @FocusState private var dishFieldFocused: Bool
    /// Abbuchen mit demselben Ablauf wie in der Kellerliste (Fach, letzte Flasche, Bewerten).
    @State private var consumer = BottleConsumer()

    private var wines: [Wine] { Array(fetchedWines) }

    /// Nur was wirklich im Keller liegt, geht an die KI.
    private var availableWines: [Wine] {
        wines.filter { !$0.isArchived && $0.quantity > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
                    } else if !viewModel.hasLabelMatches {
                        introCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wein-Berater")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProviderStatusBadge(settings: settings) { selectedTab = .settings }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: viewModel.response)
            .bottleConsumerFlow(consumer)
            .navigationDestination(for: Wine.self) { wine in
                WineDetailView(wine: wine)
            }
        }
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
            .padding(12)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PairingViewModel.suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            viewModel.dish = suggestion
                            dishFieldFocused = false
                        }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: Aktion

    private var requestButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await request() }
            } label: {
                Label("Empfehlung holen", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRequest(hasInventory: !availableWines.isEmpty))

            hintLine
        }
    }

    /// Eine Zeile unter dem Button: entweder was fehlt, oder was gleich passiert.
    @ViewBuilder
    private var hintLine: some View {
        if let provider = settings.activeProvider, let model = settings.activeModel {
            if availableWines.isEmpty {
                Text("Im Keller liegt gerade keine Flasche mit Bestand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(provider.shortName) · \(model) · \(availableWines.count) \(availableWines.count == 1 ? "Wein" : "Weine") mit Bestand")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 4) {
                Text("Ohne API-Key wird nur geprüft, ob ein Etikett das Gericht ausdrücklich nennt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("API-Key hinterlegen") { selectedTab = .settings }
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
            forceAI: forceAI
        )
    }

    // MARK: Zustände

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("\(settings.activeProvider?.shortName ?? "Die KI") schaut in deinen Keller …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var introCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wineglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("Sag mir, was du kochst.")
                .font(.headline)
            Text("Ich schlage dir bis zu drei passende Weine aus deinem eigenen Keller vor – mit Begründung und Serviertipp.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
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
                        selectedTab = .settings
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    Task { await request() }
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
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
                if let provider = viewModel.resultProvider {
                    Text(provider.shortName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .help(viewModel.resultModel)
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

            if viewModel.response == nil, !viewModel.isLoading, settings.activeProvider != nil {
                Button {
                    Task { await request(forceAI: true) }
                } label: {
                    Label("Zusätzlich die KI fragen", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Ehrliche Absage: keine Flasche im Keller passt – mit Begründung und Kauftipp.
    private func noMatchCard(_ response: PairingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keine passende Flasche im Keller", systemImage: "wineglass")
                .font(.headline)
            Text(response.generalNote.isEmpty
                 ? "Zu diesem Gericht passt nichts aus deinem aktuellen Bestand wirklich – da bin ich lieber ehrlich."
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

/// Zeigt, welcher Anbieter gerade aktiv ist – oder dass keiner eingerichtet ist.
/// Tippen führt in die Einstellungen.
struct ProviderStatusBadge: View {
    let settings: AISettings
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let provider = settings.activeProvider {
                    Image(systemName: provider.symbolName)
                    Text(provider.shortName)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Kein Anbieter")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 4)
        }
        .tint(settings.activeProvider == nil ? .orange : .accentColor)
        .accessibilityLabel(
            settings.activeProvider.map { "Aktiver Anbieter: \($0.displayName), Modell \(settings.model(for: $0))" }
                ?? "Kein Anbieter eingerichtet"
        )
    }
}

#Preview {
    AdvisorView(selectedTab: .constant(.advisor))
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
