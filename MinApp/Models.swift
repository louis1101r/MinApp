import Foundation
import SwiftData

// Lageret (SwiftData). Hver række gemmes for sig, så en ændring kun skriver den række,
// der er ændret. Loggen skrives kun ved afslutning; den aktive træning ligger i UserDefaults.
//
//   D.ex[id] per profil       -> ProfileProgress (nøgle "profil:øvelse")
//   D.log[] per profil        -> WorkoutLog (profile)
//   D.customEx[id]            -> CustomExercise
//   v, groups, inc, favs, deload, makkerens navn -> AppSettings (én række)
//
// Alle ændringer fra v3 er nye felter med standardværdier eller nye tabeller, så SwiftData
// migrerer automatisk. ExerciseProgress er v3's tabel; den læses én gang og tømmes.

/// v3: D.ex[id] (kun Louis). Beholdes i skemaet, så gamle data kan læses ved migreringen.
@Model
final class ExerciseProgress {
    @Attribute(.unique) var id: String
    var w: Double?
    var sets: Int
    var stall: Int
    var wins: Int

    init(id: String, w: Double?, sets: Int, stall: Int = 0, wins: Int = 0) {
        self.id = id
        self.w = w
        self.sets = sets
        self.stall = stall
        self.wins = wins
    }
}

/// v4: D.ex[id] for én profil.
@Model
final class ProfileProgress {
    @Attribute(.unique) var key: String
    var profile: String
    var ex: String
    var w: Double?
    var sets: Int
    var stall: Int
    var wins: Int

    init(profile: Profile, ex: String, values v: ProgressValues) {
        self.key = Self.key(profile, ex)
        self.profile = profile.rawValue
        self.ex = ex
        self.w = v.w
        self.sets = v.sets
        self.stall = v.stall
        self.wins = v.wins
    }

    static func key(_ p: Profile, _ ex: String) -> String {
        p.rawValue + ":" + ex
    }

    var values: ProgressValues {
        get { ProgressValues(w: w, sets: sets, stall: stall, wins: wins) }
        set {
            w = newValue.w
            sets = newValue.sets
            stall = newValue.stall
            wins = newValue.wins
        }
    }
}

/// D.log[] = { name, groups, date: "dd.mm.yyyy", ts, readiness, entries }
@Model
final class WorkoutLog {
    var name: String
    var groups: [String]
    var date: String
    /// Millisekunder siden 1970, som Date.now() i webappen.
    var ts: Double
    var readiness: Int
    /// entries gemt som JSON (samme form som i webappen).
    var entriesData: Data
    /// v4: hvem træningen tilhører. Alle træninger fra før makker er Louis'.
    var profile: String = "louis"

    init(_ r: LogRecord) {
        self.name = r.name
        self.groups = r.groups
        self.date = r.date
        self.ts = r.ts
        self.readiness = r.readiness
        self.entriesData = (try? JSONEncoder().encode(r.entries)) ?? Data()
        self.profile = r.profile.rawValue
    }

    var record: LogRecord {
        LogRecord(
            profile: Profile(rawValue: profile) ?? .louis,
            name: name,
            groups: groups,
            date: date,
            ts: ts,
            readiness: readiness,
            entries: (try? JSONDecoder().decode([LogEntry].self, from: entriesData)) ?? []
        )
    }
}

/// D.customEx["custom_<base36-tid>"] = { n, m, t, lo, hi, s, r, d }
@Model
final class CustomExercise {
    @Attribute(.unique) var id: String
    var n: String
    var m: String
    var t: String
    var lo: Int
    var hi: Int
    var s: Int
    var r: Int
    var d: String

    init(_ x: ExerciseDef) {
        self.id = x.id
        self.n = x.n
        self.m = x.m
        self.t = x.t
        self.lo = x.lo
        self.hi = x.hi
        self.s = x.s
        self.r = x.r
        self.d = x.d ?? ""
    }

    var def: ExerciseDef {
        ExerciseDef(id: id, n: n, m: m, t: t, lo: lo, hi: hi, s: s, r: r, d: d)
    }
}

/// Resten af D: v, groups, inc {u, l}, deload, favs + makkerens navn og deload.
@Model
final class AppSettings {
    var v: Int
    var incU: Double
    var incL: Double
    /// Louis' deload (log.length ved sidste deload).
    var deload: Int
    /// groups: { Bryst: [ids], ... } gemt som JSON.
    var groupsData: Data
    /// favs: [["Bryst","Biceps"], ...] gemt som JSON.
    var favsData: Data
    var buddyName: String = "Makker"
    var buddyDeload: Int = 0

    init(v: Int = 4, incU: Double = 2.5, incL: Double = 5, deload: Int = 0,
         groups: [String: [String]] = Catalog.defaultGroups, favs: [[String]] = []) {
        self.v = v
        self.incU = incU
        self.incL = incL
        self.deload = deload
        self.groupsData = (try? JSONEncoder().encode(groups)) ?? Data()
        self.favsData = (try? JSONEncoder().encode(favs)) ?? Data()
    }

    var groups: [String: [String]] {
        (try? JSONDecoder().decode([String: [String]].self, from: groupsData)) ?? [:]
    }

    var favs: [[String]] {
        (try? JSONDecoder().decode([[String]].self, from: favsData)) ?? []
    }

    func setGroups(_ g: [String: [String]]) {
        groupsData = (try? JSONEncoder().encode(g)) ?? groupsData
    }

    func setFavs(_ f: [[String]]) {
        favsData = (try? JSONEncoder().encode(f)) ?? favsData
    }

    func deload(_ p: Profile) -> Int {
        p == .louis ? deload : buddyDeload
    }

    func setDeload(_ p: Profile, _ v: Int) {
        if p == .louis { deload = v } else { buddyDeload = v }
    }
}

/// Indlæser hele loggen i baggrunden og bygger cachen, så appen starter hurtigt
/// selv med tusindvis af træninger.
@ModelActor
actor LogLoader {
    struct Result: Sendable {
        var logs: [Profile: [LogRecord]]
        var index: [Profile: ProfileIndex]
    }

    func load() -> Result {
        let d = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\WorkoutLog.ts)])
        let rows = (try? modelContext.fetch(d)) ?? []
        var logs: [Profile: [LogRecord]] = [.louis: [], .buddy: []]
        for row in rows {
            let r = row.record
            logs[r.profile, default: []].append(r)
        }
        var index: [Profile: ProfileIndex] = [:]
        for p in Profile.allCases {
            index[p] = ProfileIndex.build(logs[p] ?? [])
        }
        return Result(logs: logs, index: index)
    }
}
