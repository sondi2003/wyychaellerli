import AppIntents

/// Meldet den Siri-Befehl beim System an – ohne dass der Nutzer in der Kurzbefehle-App
/// etwas einrichten muss.
///
/// Apple verlangt, dass jeder Satz den App-Namen enthält. Ein freier Satz wie
/// „Siri, welcher Wein passt zu Lasagne“ ist deshalb nicht möglich; das Gericht
/// erfragt Siri im zweiten Schritt.
struct WyychaellerliShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WinePairingIntent(),
            phrases: [
                "Wein-Berater in \(.applicationName)",
                "Weinempfehlung in \(.applicationName)",
                "Welcher Wein aus \(.applicationName)",
                "Frag \(.applicationName) nach einem Wein",
                "Wine pairing in \(.applicationName)",
                "Recommend a wine in \(.applicationName)",
                "Conseiller en vins dans \(.applicationName)",
                "Recommander un vin dans \(.applicationName)",
                "Consulente per i vini in \(.applicationName)",
                "Consigliami un vino in \(.applicationName)"
            ],
            shortTitle: "Wein empfehlen",
            systemImageName: "wineglass"
        )
    }
}
