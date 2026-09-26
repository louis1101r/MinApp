import AppIntents
import Foundation

/// Forbindelse fra knapperne i Live Activity til appens logik.
/// LiveActivityIntent kører altid i appens proces; appen sætter handlingerne ved opstart.
/// (Widget-extensionen kompilerer filen for at kunne vise knapperne, men kalder den aldrig.)
@MainActor
enum RestIntentBridge {
    /// Argument: Profile.rawValue
    static var completeSet: (@MainActor (String) -> Void)?
    static var addTime: (@MainActor (String, Int) -> Void)?
}

/// "✓ Sæt færdigt": markerer personens næste sæt som færdigt og starter personens pause.
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Sæt færdigt"

    @Parameter(title: "Profil")
    var profile: String

    init() {}

    init(profile: String) {
        self.profile = profile
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentBridge.completeSet?(profile)
        return .result()
    }
}

/// "+15 sek": forlænger personens pause.
struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Forlæng pausen 15 sek"

    @Parameter(title: "Profil")
    var profile: String

    init() {}

    init(profile: String) {
        self.profile = profile
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        RestIntentBridge.addTime?(profile, 15)
        return .result()
    }
}
