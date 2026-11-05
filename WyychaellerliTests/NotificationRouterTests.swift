import Foundation
import Testing
@testable import Wyychaellerli

/// Welche Mitteilung wohin führt. Das Format ist das, was CloudKit bei einem Abo schickt
/// (`ck` → `qry` mit Abo-Kennung `sid` und Datensatz `rid`).
@Suite("Mitteilungsziel")
struct NotificationRouterTests {

    private func payload(subscription: String, record: String = "ABC-123") -> [AnyHashable: Any] {
        [
            "aps": ["alert": "Neuer Vorschlag", "sound": "default"],
            "ck": [
                "ce": 2,
                "cid": "iCloud.com.sondinetwork.weinkeller.app",
                "nid": "11111111-2222-3333-4444-555555555555",
                "qry": ["sid": subscription, "rid": record, "dbs": 2, "zid": "_defaultZone", "fo": 1]
            ] as [String: Any]
        ]
    }

    @Test("Neuer Vorschlag führt zur Prüfung dieses Vorschlags")
    func newSubmission() {
        let target = NotificationRouter.destination(for: payload(subscription: "catalog-submission-new"))
        #expect(target == .review(recordName: "ABC-123"))
    }

    @Test("Entscheid über einen eigenen Vorschlag führt zu „Meine Vorschläge“")
    func decision() {
        #expect(NotificationRouter.destination(for: payload(subscription: "catalog-submission-accepted")) == .mySubmissions)
        #expect(NotificationRouter.destination(for: payload(subscription: "catalog-submission-rejected")) == .mySubmissions)
    }

    @Test("Fremde Mitteilungen führen nirgendwohin")
    func unrelated() {
        #expect(NotificationRouter.destination(for: payload(subscription: "irgendein-anderes-abo")) == nil)
        #expect(NotificationRouter.destination(for: ["aps": ["alert": "Hallo"]]) == nil)
    }

    @MainActor
    @Test("Das Ziel wird genau einmal abgeholt")
    func consumedOnce() {
        let router = NotificationRouter()
        router.open(.mySubmissions)
        #expect(router.consume() == .mySubmissions)
        #expect(router.consume() == nil)
    }
}
