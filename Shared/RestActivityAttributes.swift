import ActivityKit
import Foundation

/// Live Activity for hviletimeren. Deles af appen og widget-extensionen.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
        /// Næste øvelse, fx "Bænkpres".
        var title: String
        /// Næste sæt, fx "Sæt 2 af 4 · 80 kg · 5–8".
        var detail: String
    }

    /// Dagens træning, fx "Bryst + Triceps".
    var workout: String
}
