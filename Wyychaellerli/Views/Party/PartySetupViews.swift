import CoreData
import SwiftUI

/// Schritt 1: Welche Flaschen stehen zur Wahl?
///
/// Nur echte Kandidaten – im Keller, nicht archiviert, mindestens eine Flasche da.
/// Der ganze Keller wäre Überforderung; vier bis acht sind eine gute Runde.
struct PartyCandidatesView: View {

    @Bindable var model: PartyViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var search = ""
    @State private var wines: [Wine] = []

    private var filtered: [Wine] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return wines }
        return wines.filter {
            $0.name.lowercased().contains(query)
                || $0.producer.lowercased().contains(query)
                || $0.grape.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField("Anlass, z. B. Silvester", text: Binding(
                        get: { model.state.title },
                        set: { model.setTitle($0) }
                    ))
                } header: {
                    Text("Anlass")
                } footer: {
                    Text("Steht später in der Historie. Leer lassen geht auch, dann zählt das Datum.")
                }

                Section {
                    if filtered.isEmpty {
                        Text(wines.isEmpty
                             ? "Im Keller liegt gerade keine Flasche mit Bestand."
                             : "Nichts gefunden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { wine in
                        Button {
                            model.toggleCandidate(wine)
                        } label: {
                            HStack(spacing: 12) {
                                LabelThumbnail(wine: wine, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wine.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(wine.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    // Beim Zusammenstellen hilfreich: Steht die Flasche
                                    // überhaupt griffbereit, oder muss jemand in den Keller?
                                    if !wine.storageSummary.isEmpty {
                                        Label(wine.storageSummary, systemImage: "square.grid.3x3")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                // Der Text bekommt den freien Platz zuerst, sonst teilt
                                // er ihn sich mit dem Spacer und bricht zu früh ab.
                                .layoutPriority(1)
                                Spacer(minLength: 4)
                                Image(systemName: model.isSelected(wine) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(model.isSelected(wine) ? Color.accentColor : Color.secondary.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Zur Wahl stellen")
                }
            }
            .searchable(text: $search, prompt: "Wein suchen")

            footer
        }
        .onAppear {
            wines = PartyViewModel.selectableWines(in: context)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(model.state.candidateIDs.count) gewählt")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.canStartGuests {
                    // Die Stimmenzahl folgt automatisch der Zahl der Flaschen.
                    Text("\(model.state.votesPerGuest) \(model.state.votesPerGuest == 1 ? "Stimme" : "Stimmen") je Gast")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                model.goToGuests(in: context)
            } label: {
                Text("Weiter zu den Gästen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartGuests)

            if !model.canStartGuests {
                Text("Mindestens zwei Flaschen, sonst gibt es nichts zu wählen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
}

/// Schritt 2: Wer ist da?
///
/// Name, Kosename, Initialen – Hauptsache, jeder erkennt sich wieder. Der Name ist
/// zugleich die einzige Sicherung dagegen, dass jemand zweimal stimmt: Auf dem Gerät
/// sieht man, wer schon dran war.
struct PartyGuestsView: View {

    @Bindable var model: PartyViewModel
    /// Läuft der geführte Zugriff? Wenn nicht, wird hier der Weg dorthin gezeigt.
    var isGuidedAccessActive = false

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        TextField("Name oder Kosename", text: $name)
                            .focused($isFocused)
                            .submitLabel(.done)
                            .onSubmit { add() }
                        Button {
                            add()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Hinzufügen")
                } footer: {
                    Text("Auch der Gastgeber gehört in die Liste, wenn er mitstimmen will.")
                }

                Section {
                    if model.state.guests.isEmpty {
                        Text("Noch niemand erfasst.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.state.guests) { guest in
                        HStack {
                            Text(guest.name)
                            Spacer()
                            if guest.hasVoted {
                                Label("hat gestimmt", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.green)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.removeGuest(guest)
                            } label: {
                                Label("Entfernen", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Anwesend (\(model.state.guests.count))")
                }

                // Kurz vor dem Weitergeben ist der richtige Moment für den Hinweis.
                Section {
                    GuidedAccessCard(isActive: isGuidedAccessActive)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            footer
        }
        .onAppear { isFocused = model.state.guests.isEmpty }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                model.startVoting()
            } label: {
                Text(model.state.totalVotes > 0 ? "Weiter abstimmen" : "Abstimmung starten")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartVoting || model.state.pendingGuests.isEmpty)

            // Zurück zur Auswahl geht nur, solange noch keine Stimme gefallen ist –
            // sonst würden Kandidaten unter den bereits abgegebenen Stimmen wegfallen.
            if model.state.totalVotes == 0 {
                Button("Zurück zur Flaschenauswahl") {
                    model.backToCandidates()
                }
                .font(.subheadline)
            } else if model.state.pendingGuests.isEmpty {
                Button("Jetzt auswerten") {
                    model.evaluateNow()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func add() {
        model.addGuest(named: name)
        name = ""
        isFocused = true
    }
}
