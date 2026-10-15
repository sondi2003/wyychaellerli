import Foundation
import LocalAuthentication

/// Der Riegel vor dem Party-Modus – **die Gerätesperre selbst**, kein eigener Code.
///
/// Der erste Entwurf hatte einen zweiten Code, den man festlegen, merken und über
/// iCloud verteilen musste. Richard hat am 10.9.2026 vorgeschlagen, stattdessen zu
/// nehmen, was ohnehin da ist. Das ist in jeder Hinsicht besser:
///
/// - Nichts einzurichten, nichts zu merken, nichts zu synchronisieren.
/// - Gilt sofort auf jedem Gerät – iPhone, iPad, auch bei der Partnerin.
/// - Kein „Code vergessen“: Wer sein iPhone entsperren kann, kommt hier heraus.
/// - Ein Gast, der es versucht, scheitert an Face ID (falsches Gesicht) und landet bei
///   der Code-Eingabe, die er nicht kennt.
///
/// `deviceOwnerAuthentication` heisst: Face ID oder Touch ID, und wenn das nicht geht,
/// der Gerätecode. Genau die Kette, die iOS auch sonst benutzt.
enum PartyLock {

    /// `false`, wenn auf dem Gerät gar keine Sperre eingerichtet ist. Dann darf der
    /// Party-Modus nicht starten – man käme nicht mehr heraus.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Wie iOS hier entsperrt: „Face ID“, „Touch ID“ oder „den Code“.
    static var methodName: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return tr("den Gerätecode")
        }
        switch context.biometryType {
        case .faceID:  return tr("Face ID")
        case .touchID: return tr("Touch ID")
        default:       return tr("den Gerätecode")
        }
    }

    /// Fragt die Gerätesperre ab. `true`, wenn entsperrt wurde.
    static func unlock(reason: String) async -> Bool {
        let context = LAContext()
        // Kein eigener Ausweichtext: Der Systemtext führt korrekt zur Code-Eingabe.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
