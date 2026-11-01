import Foundation

// Den rene del af Google Health-forbindelsen (kun Foundation, så den kan testes lokalt).

/// En træning, der venter på at blive sendt.
struct GoogleWorkout: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var startMs: Double
    var dur: Int
    var utcOffset: Int

    init(name: String, startMs: Double, dur: Int, utcOffset: Int) {
        // Samme træning får altid samme id, så en gentaget afsendelse ikke laver en dublet.
        self.id = "minapp-\(Int64(startMs))"
        self.name = name
        self.startMs = startMs
        self.dur = dur
        self.utcOffset = utcOffset
    }

    /// Så lang en træning er sikkert en glemt "Afslut", så den sendes ikke uden at spørge.
    static let longDuration = 4 * 3600

    var isLong: Bool { dur > Self.longDuration }

    /// Kroppen til POST .../users/me/dataTypes/exercise/dataPoints
    func body() -> [String: Any] {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let start = Date(timeIntervalSince1970: startMs / 1000)
        let end = start.addingTimeInterval(Double(dur))
        let offset = "\(utcOffset)s"
        let interval: [String: Any] = [
            "startTime": f.string(from: start),
            "startUtcOffset": offset,
            "endTime": f.string(from: end),
            "endUtcOffset": offset
        ]
        let exercise: [String: Any] = [
            "interval": interval,
            "exerciseType": "STRENGTH_TRAINING",
            "displayName": name,
            "activeDuration": "\(dur)s"
        ]
        return [
            "name": "users/me/dataTypes/exercise/dataPoints/\(id)",
            "dataSource": ["recordingMethod": "ACTIVELY_MEASURED"],
            "exercise": exercise
        ]
    }
}
