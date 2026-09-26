import ActivityKit
import Foundation

/// Live Activity for hviletimerne (én række per person). Deles af appen og widget-extensionen.
/// (Afløser RestActivityAttributes fra før makker; en ny type, så gamle aktiviteter ikke
/// forsøges læst i det nye format.)
struct RestAttributes: ActivityAttributes {
    struct Person: Codable, Hashable {
        /// Profile.rawValue ("louis" / "buddy").
        var profile: String
        var name: String
        /// nil = personen holder ikke pause.
        var startDate: Date?
        var endDate: Date?
        /// Næste øvelse, fx "Bænkpres".
        var title: String
        /// Næste sæt, fx "Sæt 2 af 4 · 80 kg · 5–8".
        var detail: String
        /// Seneste sæt, fx "80 × 8".
        var last: String
    }

    struct ContentState: Codable, Hashable {
        var people: [Person]
    }

    /// Dagens træning, fx "Bryst + Triceps".
    var workout: String
}
