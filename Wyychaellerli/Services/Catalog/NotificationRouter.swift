import CloudKit
import Observation
import UserNotifications

/// Wohin eine angetippte Katalog-Mitteilung führen soll.
///
/// Der `AppDelegate` empfängt den Tipp, kennt aber die Oberfläche nicht; `ContentView` und
/// die Einstellungen kennen sie, aber nicht den Delegate. Der Router liegt dazwischen. Er
/// hält das Ziel, bis jemand es abgeholt hat – wird die App erst durch den Tipp gestartet,
/// ist die Oberfläche beim Eintreffen noch gar nicht da.
@MainActor
@Observable
final class NotificationRouter {

    static let shared = NotificationRouter()

    enum Destination: Equatable {
        /// Neuer Vorschlag (Admin): direkt dessen Prüfung. `recordName` nennt den Datensatz,
        /// damit nicht die Liste, sondern der Vorschlag selbst aufgeht.
        case review(recordName: String?)
        /// Entscheid über einen eigenen Vorschlag: „Meine Vorschläge“.
        case mySubmissions
    }

    /// Gesetzt, bis die Oberfläche es verbraucht (`consume()`).
    private(set) var destination: Destination?

    func open(_ destination: Destination) {
        self.destination = destination
    }

    /// Holt das Ziel ab und löscht es – jedes Ziel führt genau einmal irgendwohin.
    func consume() -> Destination? {
        defer { destination = nil }
        return destination
    }

    /// Das Ziel einer Mitteilung. Ohne Katalog-Abo (oder bei fremden Mitteilungen) `nil`.
    nonisolated static func destination(for userInfo: [AnyHashable: Any]) -> Destination? {
        guard let query = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification else {
            return nil
        }
        switch query.subscriptionID {
        case CatalogStore.SubscriptionID.newSubmission:
            // `recordID` ist nicht in jeder Fassung der Nutzlast gefüllt; der Name steht
            // auch roh unter `ck → qry → rid`. Ohne ihn öffnet sich die Liste statt des Vorschlags.
            let raw = ((userInfo["ck"] as? [String: Any])?["qry"] as? [String: Any])?["rid"] as? String
            return .review(recordName: query.recordID?.recordName ?? raw)
        case CatalogStore.SubscriptionID.accepted, CatalogStore.SubscriptionID.rejected:
            return .mySubmissions
        default:
            return nil
        }
    }
}
