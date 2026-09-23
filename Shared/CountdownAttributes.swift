import ActivityKit
import Foundation

struct CountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
    }

    var title: String
}
