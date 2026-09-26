import Foundation

// Rene værdityper uden SwiftUI/SwiftData, så logikken kan testes lokalt med
// tools/logic-tests (se CLAUDE.md).

/// De to profiler. Louis er fast; makkerens navn kan ændres.
enum Profile: String, Codable, CaseIterable, Hashable, Sendable {
    case louis, buddy
}

/// Ét sæt i en logpost: { w, r, rir }
struct LogSet: Codable, Hashable, Sendable {
    var w: Double
    var r: Double
    var rir: Double
}

/// { ex: id, sets: [...] }
struct LogEntry: Codable, Hashable, Sendable {
    var ex: String
    var sets: [LogSet]
}

/// En logpost (D.log[]) for én profil.
struct LogRecord: Hashable, Sendable {
    var profile: Profile
    var name: String
    var groups: [String]
    var date: String
    var ts: Double
    var readiness: Int
    var entries: [LogEntry]
}

/// D.ex[id] = { w, sets, stall, wins }
struct ProgressValues: Hashable, Sendable {
    var w: Double?
    var sets: Int
    var stall: Int
    var wins: Int
}

/// Alt, der hører til én profil.
struct ProfileData: Sendable {
    var name: String
    var ex: [String: ProgressValues]
    var log: [LogRecord]
    var deload: Int
}

/// Hele datasættet (D v4): fælles data + Louis + evt. makker.
struct BackupData: Sendable {
    /// Formatet backuppen var i (2, 3 eller 4).
    var sourceVersion: Int
    var groups: [String: [String]]
    var incU: Double
    var incL: Double
    var customEx: [ExerciseDef]
    var favs: [[String]]
    var louis: ProfileData
    /// nil i v2/v3-backups.
    var buddy: ProfileData?
}

// MARK: - Igangværende træning (treg_active)

/// Værdierne er strenge fra inputfelterne, som i webappen.
struct ActiveSet: Codable, Hashable, Sendable {
    var w: String = ""
    var r: String = ""
    var rir: String = ""
    var done: Bool = false
}

/// Én persons del af en øvelse: egen målvægt og egne sæt.
struct ActivePerson: Codable, Hashable, Sendable {
    var target: Double?
    var sets: [ActiveSet]
}

struct ActiveExercise: Codable, Hashable, Sendable {
    var id: String
    /// Nøgle: Profile.rawValue
    var people: [String: ActivePerson]

    subscript(p: Profile) -> ActivePerson? {
        get { people[p.rawValue] }
        set { people[p.rawValue] = newValue }
    }
}

struct ActiveSession: Codable, Hashable, Sendable {
    var name: String
    var groups: [String]
    /// [.louis] = træn alene, [.louis, .buddy] = træn sammen.
    var profiles: [Profile]
    /// Dagsform per profil (nøgle: Profile.rawValue).
    var readiness: [String: Int]
    var ex: [ActiveExercise]

    var together: Bool { profiles.count > 1 }

    func readiness(_ p: Profile) -> Int {
        readiness[p.rawValue] ?? 3
    }
}

/// treg_active fra før makker (én person). Læses én gang og konverteres til Louis.
struct LegacyActiveSession: Codable {
    struct Ex: Codable {
        var id: String
        var target: Double?
        var sets: [ActiveSet]
    }
    var name: String
    var groups: [String]?
    var readiness: Int
    var ex: [Ex]

    var converted: ActiveSession {
        ActiveSession(
            name: name,
            groups: groups ?? [],
            profiles: [.louis],
            readiness: [Profile.louis.rawValue: readiness],
            ex: ex.map { e in
                ActiveExercise(id: e.id, people: [Profile.louis.rawValue: ActivePerson(target: e.target, sets: e.sets)])
            }
        )
    }
}
