import Foundation

// Webappens rene logik (afsnit 5), uafhængig af lager og skærm, så den kan testes lokalt.

/// Et opslag i EX (indbyggede + egne øvelser).
typealias ExLookup = (String) -> ExerciseDef?

enum Logic {
    // MARK: - muskelgrupper

    static func tgOf(_ id: String, _ EX: ExLookup) -> String {
        let m = EX(id)?.m ?? ""
        return Catalog.tgMap[m] ?? m
    }

    static func sortGroups(_ gs: [String]) -> [String] {
        func idx(_ g: String) -> Int { Catalog.sessionOrder.firstIndex(of: g) ?? -1 }
        return gs.sorted { idx($0) < idx($1) }
    }

    static func groupsOfIds(_ ids: [String], _ EX: ExLookup) -> [String] {
        var gs: [String] = []
        for id in ids where EX(id) != nil {
            let g = tgOf(id, EX)
            if !gs.contains(g) { gs.append(g) }
        }
        return sortGroups(gs)
    }

    /// logGroups(l): gemte grupper, ellers udledt af øvelserne med sæt.
    static func logGroups(_ groups: [String]?, _ entries: [LogEntry], _ EX: ExLookup) -> [String] {
        groups ?? groupsOfIds(entries.filter { !$0.sets.isEmpty }.map(\.ex), EX)
    }

    // MARK: - afslutning

    /// Kun sæt med vægt og reps > 0. "i tanken" = 2, hvis tom.
    static func loggedSets(_ sets: [ActiveSet]) -> [LogSet] {
        sets.compactMap { v in
            guard let w = num(v.w), let r = num(v.r), r > 0 else { return nil }
            return LogSet(w: w, r: r, rir: num(v.rir) ?? 2)
        }
    }

    /// Progressionen i finish() for én øvelse. `sets` må ikke være tom.
    /// Returnerer beskeden til slutskærmen.
    static func progress(_ s: inout ProgressValues, x: ExerciseDef, sets: [LogSet], step: Double, readiness: Int) -> String {
        let minR = sets.map(\.r).min() ?? 0
        let top = sets.map(\.w).max() ?? 0
        let lastRir = sets[sets.count - 1].rir
        let hi = Double(x.hi)
        let lo = Double(x.lo)
        var msg: String
        if minR >= hi && lastRir >= 3 {
            s.w = rnd(top + step * 2, step / 2); s.stall = 0; s.wins += 1; msg = "klart over målet"
        } else if minR >= hi {
            s.w = rnd(top + step, step / 2); s.stall = 0; s.wins += 1; msg = "alle sæt i toppen"
        } else if minR >= lo {
            s.w = top; s.stall = 0; msg = "hold vægten, jagt gentagelser"
        } else {
            s.stall += 1
            if s.stall >= 2 {
                s.w = rnd(top * 0.9, step / 2); s.stall = 0; s.wins = 0; s.sets = x.s
                msg = "under målet to gange, ned 10 %"
            } else {
                s.w = top; msg = "under målet, samme vægt igen"
            }
        }
        if s.wins >= 3 && s.sets < x.s + 2 && readiness >= 4 {
            s.sets += 1; s.wins = 0; msg += ", plus ét sæt"
        }
        return msg
    }

    /// makeSessionEx(): antal sæt og målvægt for én person.
    static func sessionPerson(_ s: ProgressValues, readiness rd: Int, inc: Double) -> ActivePerson {
        let n = max(2, s.sets - (rd == 1 ? 1 : 0))
        let target = s.w.map { rnd($0 * Catalog.readyMult(rd), inc / 2) }
        return ActivePerson(target: target, sets: Array(repeating: ActiveSet(), count: n))
    }

    /// doDeload() for én øvelse.
    static func deload(_ s: inout ProgressValues, x: ExerciseDef, inc: Double) {
        if let w = s.w, w != 0 { s.w = rnd(w * 0.9, inc / 2) }
        s.stall = 0
        s.wins = 0
        s.sets = x.s
    }

    static func dateString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        return String(format: "%02ld.%02ld.%ld", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }
}

// MARK: - Cache over loggen (hurtig med mange træninger)

/// En række fra exStats(id).
struct StatRow: Hashable, Sendable {
    var date: String
    var best: LogSet
    var e1: Double
    var top: Double
    var vol: Double
    var sets: Int
}

/// Det, listen "Træninger" og volumen-grafen skal bruge fra en logpost.
struct LogSummary: Hashable, Sendable {
    var name: String
    var date: String
    var ts: Double
    var setCount: Int
    var volume: Double
}

/// Forudberegnet over én profils log. Bygges én gang og udvides ved hver afslutning,
/// så forsiden og Udvikling ikke gennemløber hele loggen ved hver visning.
struct ProfileIndex: Sendable {
    private(set) var lastTrained: [String: Double] = [:]
    private(set) var stats: [String: [StatRow]] = [:]
    private(set) var summaries: [LogSummary] = []

    var count: Int { summaries.count }

    static func build(_ logs: [LogRecord]) -> ProfileIndex {
        var ix = ProfileIndex()
        ix.summaries.reserveCapacity(logs.count)
        for l in logs { ix.add(l) }
        return ix
    }

    mutating func add(_ l: LogRecord) {
        for g in l.groups {
            if let t = lastTrained[g], t >= l.ts { continue }
            lastTrained[g] = l.ts
        }
        var setCount = 0
        var volume = 0.0
        for e in l.entries {
            setCount += e.sets.count
            guard !e.sets.isEmpty else { continue }
            var best = e.sets[0]
            var be = e1rm(best.w, best.r, best.rir)
            var top = 0.0
            var vol = 0.0
            for x in e.sets {
                let v = e1rm(x.w, x.r, x.rir)
                if v > be { be = v; best = x }
                if x.w > top { top = x.w }
                vol += x.w * x.r
            }
            volume += vol
            stats[e.ex, default: []].append(
                StatRow(date: l.date, best: best, e1: be, top: top, vol: vol, sets: e.sets.count)
            )
        }
        summaries.append(LogSummary(name: l.name, date: l.date, ts: l.ts, setCount: setCount, volume: volume))
    }

    func exStats(_ id: String) -> [StatRow] {
        stats[id] ?? []
    }
}
