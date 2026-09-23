import AppIntents
import Foundation

/// Forbindelse fra knapperne i Live Activity til appens logik.
/// LiveActivityIntent kører altid i appens proces; appen sætter handlingerne ved opstart.
/// (Widget-extensionen kompilerer filen for at kunne vise knapperne, men kalder den aldrig.)
@MainActor
enum RestIntentBridge {
    static var completeSet: (@MainActor () -> Void)?
    static var addTime: (@MainActor (Int) -> Void)?
}

/// "✓ Sæt færdigt": markerer det sæt, Live Activity viser som det næste, og starter pausen.
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Sæt færdigt"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentBridge.completeSet?()
        return .result()
    }
}

/// "+15 sek": forlænger pausen.
struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Forlæng pausen 15 sek"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentBridge.addTime?(15)
        return .result()
    }
}
