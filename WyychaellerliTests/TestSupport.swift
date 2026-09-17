import CoreData
import Foundation
@testable import Wyychaellerli

/// Ein frischer Core-Data-Stack im Arbeitsspeicher, ohne CloudKit.
///
/// Jeder Test bekommt seinen eigenen: Sonst schleppen Tests Zustand voneinander mit,
/// und ein Fehlschlag hinge davon ab, in welcher Reihenfolge sie liefen.
@MainActor
enum TestStack {

    static func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true, useCloudKit: false).viewContext
    }

    /// Keller mit einer Flasche darin – die Ausgangslage der meisten Tests.
    @discardableResult
    static func makeWine(
        in context: NSManagedObjectContext,
        name: String = "Testwein",
        producer: String = "",
        vintage: Int = 2020,
        grape: String = "Merlot",
        country: String = "",
        type: WineType = .red,
        quantity: Int = 1,
        alcoholPercent: Double = 0,
        drinkFrom: Int = 0,
        drinkTo: Int = 0,
        foodPairings: [String] = [],
        isArchived: Bool = false
    ) -> Wine {
        Wine.create(
            in: context,
            cellar: Cellar.active(in: context),
            name: name,
            producer: producer,
            vintage: vintage,
            grape: grape,
            country: country,
            type: type,
            quantity: quantity,
            alcoholPercent: alcoholPercent,
            foodPairings: foodPairings,
            drinkFrom: drinkFrom,
            drinkTo: drinkTo,
            isArchived: isArchived
        )
    }
}
