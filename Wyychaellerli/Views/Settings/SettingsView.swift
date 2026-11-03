import SwiftUI

/// Einstellungen: Sprache, Darstellung, Freigabe, Katalog, KI und Hilfe.
///
/// Öffnet sich als Blatt über das Zahnrad im Keller (kein eigener Reiter mehr – man
/// braucht sie selten). Der Anbieter mit hinterlegtem Key ist automatisch aktiv. Nur
/// wenn mehrere Keys hinterlegt sind, erscheint eine Auswahl, welcher bevorzugt wird.
struct SettingsView: View {

    /// Als Blatt geöffnet: mit „Fertig“ oben rechts.
    var isSheet = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AISettings.self) private var settings
    @Environment(CurrentRater.self) private var rater
    @Environment(LocalAIStatus.self) private var localAI
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var isShowingWalkthrough = false
    @State private var didResetTips = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Sprache", selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(verbatim: option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Sprache")
                } footer: {
                    Text("Gilt für die ganze App, auch für die Antworten der KI.")
                }

                Section {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { option in
                            Label(option.title, systemImage: option.symbolName)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text(appearance == .system
                         ? "Die App folgt der Einstellung von iOS."
                         : "Die App bleibt \(appearance.title.lowercased()), unabhängig vom System.")
                }

                Section {
                    TextField("Dein Name", text: Binding(
                        get: { rater.name },
                        set: { rater.name = $0 }
                    ))
                    .textContentType(.givenName)
                } header: {
                    Text("Bewertungen")
                } footer: {
                    Text("Steht bei deinen Weinbewertungen, damit beide Seiten sehen, von wem sie stammen. Den Namen kann iOS nicht selbst ermitteln, deshalb die Nachfrage.")
                }

                CellarSharingSection()

                CatalogSettingsSection()

                Section {
                    localRow(.onDevice, hint: tr("Ab iPhone 15 Pro, Apple Intelligence eingeschaltet"))
                    localRow(.privateCloud, hint: tr("Ab iOS 27, ohne Key"))
                    if settings.activeProvider != nil {
                        Toggle("Externe KI zuerst fragen", isOn: $settings.prefersExternal)
                    }
                } header: {
                    Text("Lokale KI")
                } footer: {
                    if localAI.sources.isEmpty {
                        Text("Keines der lokalen Modelle ist gerade nutzbar – das Gerät unterstützt Apple Intelligence nicht, es ist ausgeschaltet, oder das Modell versteht die gewählte Sprache nicht. Ein API-Key unten ersetzt es.")
                    } else {
                        Text("Der Wein-Berater und das Auslesen der Etiketten versuchen zuerst Apple. Die externe KI unten ist freiwillig und kommt nur zum Zug, wenn das nicht klappt.")
                    }
                }

                Section {
                    ForEach(AIProvider.allCases) { provider in
                        NavigationLink {
                            ProviderSettingsView(provider: provider)
                        } label: {
                            providerRow(provider)
                        }
                    }
                    // Nur nötig, wenn mehrere Keys hinterlegt sind – sonst ist der aktive
                    // Anbieter ohnehin eindeutig.
                    if settings.hasMultipleProviders {
                        Picker("Bevorzugt", selection: $settings.preferredProvider) {
                            ForEach(settings.configuredProviders) { provider in
                                Label(provider.displayName, systemImage: provider.symbolName)
                                    .tag(provider)
                            }
                        }
                    }
                } header: {
                    Text("Anbieter")
                } footer: {
                    if settings.hasMultipleProviders {
                        Text("Du hast mehrere Keys hinterlegt. Der bevorzugte wird für Empfehlungen verwendet. API-Keys liegen ausschliesslich in der Keychain dieses Geräts.")
                    } else if settings.activeProvider == nil {
                        Text("Freiwillig: Mit einem API-Key kann zusätzlich eine externe KI antworten. Keys liegen ausschliesslich in der Keychain dieses Geräts.")
                    } else {
                        Text("Der Anbieter mit hinterlegtem Key wird automatisch verwendet. API-Keys liegen ausschliesslich in der Keychain dieses Geräts und gehen nur an den jeweiligen Anbieter.")
                    }
                }

                Section {
                    Button {
                        isShowingWalkthrough = true
                    } label: {
                        Label("Einführung nochmals anzeigen", systemImage: "questionmark.circle")
                    }
                    Button {
                        QuickTips.showAgain()
                        didResetTips = true
                    } label: {
                        Label(didResetTips ? "Tipps werden wieder gezeigt" : "Tipps nochmals zeigen", systemImage: "lightbulb")
                    }
                    .disabled(didResetTips)
                } header: {
                    Text("Hilfe")
                } footer: {
                    Text("Die Einführung sind die sechs Seiten vom ersten Start. Die Tipps sind die kleinen Hinweise am Ort – im Regal, beim Scannen, an der Liste –, die nach dem ersten Mal verschwinden.")
                }

            }
            .navigationTitle("Einstellungen")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingWalkthrough) {
                WalkthroughView()
            }
        }
    }

    /// Kompakte Zeile pro Anbieter: Name, Zustand und ein Tipp führt zu den Details.
    /// Eine Zeile je lokalem Modell: Häkchen, wenn es jetzt nutzbar ist.
    private func localRow(_ source: LocalAISource, hint: String) -> some View {
        let isUsable = localAI.sources.contains(source)
        return HStack(spacing: 12) {
            Image(systemName: source.symbolName)
                .frame(width: 28)
                .foregroundStyle(isUsable ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: source.displayName)
                Text(verbatim: hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isUsable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isUsable ? Color.green : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        HStack(spacing: 12) {
            Image(systemName: provider.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            Text(provider.displayName)
            Spacer()
            if settings.activeProvider == provider {
                Text("Aktiv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if settings.hasAPIKey(for: provider) {
                Text("Key hinterlegt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Kein Key")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

}

// MARK: - Eigene Seite pro Anbieter

/// Key und Modellnamen eines Anbieters.
///
/// Bewusst eine eigene Seite statt dreier Abschnitte untereinander: Mit drei Anbietern
/// war die Einstellungsseite so lang, dass Erscheinungsbild, Freigabe und Siri nach unten
/// gedrückt wurden. Aufklappbare Abschnitte wären eine Alternative, aber im `Form` sind
/// sie fummelig und verbergen den Zustand; eine Zeile mit Zustand plus Detailseite ist
/// das übliche iOS-Muster.
struct ProviderSettingsView: View {

    let provider: AIProvider

    @Environment(AISettings.self) private var settings
    @State private var apiKey = ""
    @State private var model = ""
    @State private var fastModel = ""
    @State private var isKeyVisible = false
    @State private var keychainError: String?

    private var isActive: Bool { settings.activeProvider == provider }

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if isKeyVisible {
                            TextField("API-Key", text: $apiKey)
                        } else {
                            SecureField("API-Key", text: $apiKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isKeyVisible ? "Key verbergen" : "Key anzeigen")
                }

                if settings.hasAPIKey(for: provider) {
                    Button(role: .destructive) {
                        apiKey = ""
                        isKeyVisible = false
                    } label: {
                        Label("API-Key entfernen", systemImage: "trash")
                    }
                }

                if let keychainError {
                    Text(keychainError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Zugang")
            } footer: {
                Text(provider.apiKeyHint)
            }

            Section {
                LabeledContent("Empfehlungen") {
                    TextField(provider.defaultModel, text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.callout.monospaced())
                }

                LabeledContent("Siri") {
                    TextField(provider.defaultFastModel, text: $fastModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.callout.monospaced())
                }
            } header: {
                Text("Modelle")
            } footer: {
                Text("Leer lassen, um die Vorgaben zu verwenden. Für Siri wird ein schnelleres Modell genutzt, weil Siri nicht lange wartet.")
            }

            if isActive {
                Section {
                    Label("Dieser Anbieter ist aktiv.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = settings.apiKey(for: provider)
            model = settings.customModel(for: provider)
            fastModel = settings.customFastModel(for: provider)
        }
        .onChange(of: apiKey) { _, newValue in
            do {
                try settings.setAPIKey(newValue, for: provider)
                keychainError = nil
            } catch {
                keychainError = error.localizedDescription
            }
        }
        .onChange(of: model) { _, newValue in
            settings.setCustomModel(newValue, for: provider)
        }
        .onChange(of: fastModel) { _, newValue in
            settings.setCustomFastModel(newValue, for: provider)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AISettings(defaults: PreviewData.defaults))
        .environment(CatalogCenter())
}
