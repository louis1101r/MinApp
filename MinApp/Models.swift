import Foundation
import SwiftData

// Datamodellen spejler webappens D (v3). Feltnavnene er de samme, så en JSON-backup
// fra webappen senere kan importeres 1:1.
//
//   D.ex[id]        -> ExerciseProgress
//   D.log[]         -> WorkoutLog
//   D.customEx[id]  -> CustomExercise
//   D.v, D.groups, D.inc, D.deload, D.favs -> AppSettings (én række)

/// D.ex[id] = { w, sets, stall, wins }
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

/// Ét sæt i en logpost: { w, r, rir }
struct LogSet: Codable, Hashable {
    var w: Double
    var r: Double
    var rir: Double
}

/// { ex: id, sets: [...] }
struct LogEntry: Codable, Hashable {
    var ex: String
    var sets: [LogSet]
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

    init(name: String, groups: [String], date: String, ts: Double, readiness: Int, entries: [LogEntry]) {
        self.name = name
        self.groups = groups
        self.date = date
        self.ts = ts
        self.readiness = readiness
        self.entriesData = (try? JSONEncoder().encode(entries)) ?? Data()
    }

    var entries: [LogEntry] {
        (try? JSONDecoder().decode([LogEntry].self, from: entriesData)) ?? []
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

    init(id: String, n: String, m: String, t: String, lo: Int, hi: Int, s: Int, r: Int, d: String) {
        self.id = id
        self.n = n
        self.m = m
        self.t = t
        self.lo = lo
        self.hi = hi
        self.s = s
        self.r = r
        self.d = d
    }

    var def: ExerciseDef {
        ExerciseDef(id: id, n: n, m: m, t: t, lo: lo, hi: hi, s: s, r: r, d: d)
    }
}

/// Resten af D: v, groups, inc {u, l}, deload, favs.
@Model
final class AppSettings {
    var v: Int
    var incU: Double
    var incL: Double
    var deload: Int
    /// groups: { Bryst: [ids], ... } gemt som JSON.
    var groupsData: Data
    /// favs: [["Bryst","Biceps"], ...] gemt som JSON.
    var favsData: Data

    init(v: Int = 3, incU: Double = 2.5, incL: Double = 5, deload: Int = 0,
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
}

// MARK: - Igangværende træning (treg_active)

/// Værdierne er strenge fra inputfelterne, som i webappen.
struct ActiveSet: Codable, Hashable {
    var w: String = ""
    var r: String = ""
    var rir: String = ""
    var done: Bool = false
}

struct ActiveExercise: Codable, Hashable {
    var id: String
    var target: Double?
    var sets: [ActiveSet]
}

struct ActiveSession: Codable, Hashable {
    var name: String
    var groups: [String]
    var readiness: Int
    var ex: [ActiveExercise]
}
