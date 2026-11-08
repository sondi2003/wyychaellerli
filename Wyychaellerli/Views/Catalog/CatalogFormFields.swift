import SwiftUI
import UIKit

/// Die Felder eines Katalogeintrags – gleich beim Prüfen eines Vorschlags und beim
/// Bearbeiten im Katalog.
///
/// Jedes Feld hat links eine feste Beschriftung. Ein blosser Platzhalter verschwindet,
/// sobald etwas drinsteht – dann stand „2026“ oder „0“ da ohne Hinweis, wofür.
struct CatalogFormFields: View {

    @Binding var entry: CatalogWine

    var body: some View {
        Section("Wein") {
            field("Name", text: $entry.name)
            field("Produzent", text: $entry.producer)
            LabeledContent("Jahrgang") {
                TextField("Jahrgang", value: $entry.vintage, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Weinart", selection: $entry.typeRaw) {
                ForEach(WineType.allCases) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
        }

        Section("Herkunft") {
            field("Rebsorte", text: $entry.grape)
            field("Region", text: $entry.region)
            field("Land", text: $entry.country)
            LabeledContent("Alkohol (Prozent)") {
                TextField("Alkohol (Prozent)", value: $entry.alcoholPercent, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }

        Section {
            TextField("z. B. Rindfleisch, Hartkäse", text: foodBinding, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Passt zu")
        } footer: {
            Text("Kommagetrennt, auf Deutsch. Der Filter „Passt zu“ im Keller gruppiert danach.")
        }

        Section {
            GtinField(gtins: $entry.gtins)
        } header: {
            Text("Strichcode")
        } footer: {
            Text("Mehrere durch Komma trennen, zum Beispiel für verschiedene Flaschengrössen. Der Jahrgang entscheidet weiter, welcher Eintrag gemeint ist.")
        }
    }

    private var foodBinding: Binding<String> {
        Binding(
            get: { entry.foodPairings.joined(separator: ", ") },
            set: { text in
                entry.foodPairings = text.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Eingabe der Strichcodes eines Katalogeintrags.
///
/// Der Text bleibt, wie getippt; ins Modell gehen nur Codes, die die Prüfziffer bestehen.
/// Sonst verschwände eine halb getippte Ziffernfolge bei jedem Tastendruck.
private struct GtinField: View {

    @Binding var gtins: [String]
    @State private var text = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Ziffern, durch Komma getrennt", text: $text, axis: .vertical)
                .keyboardType(.numbersAndPunctuation)
                .monospacedDigit()
            if Barcode.hasInvalidEntry(in: text) {
                Label("Ein Code besteht die Prüfziffer nicht und wird nicht gespeichert.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            text = gtins.joined(separator: ", ")
        }
        .onChange(of: text) { _, newValue in
            gtins = Barcode.list(from: newValue)
        }
    }
}
