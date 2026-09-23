import Foundation
import Observation
import SwiftData
import UIKit

/// En linje på slutskærmen efter finish().
struct Adjustment: Identifiable, Hashable {
    let id = UUID()
    var n: String
    var from: Double?
    var to: Double
    var msg: String
}

/// Port af webappens logik (afsnit 5 i docs/traeningsapp-kontekst.md).
/// Funktionsnavnene svarer til webappens, så de kan sammenlignes linje for linje.
@MainActor
@Observable
final class TrainingStore {
    private let context: ModelContext
    private(set) var settings: AppSettings
    private var progress: [String: ExerciseProgress] = [:]
    private(set) var log: [WorkoutLog] = []
    private var customEx: [String: ExerciseDef] = [:]

    /// D.groups og D.favs, spejlet fra settings.
    private(set) var groups: [String: [String]] = [:]
    private(set) var favs: [[String]] = []

    private(set) var active: ActiveSession?
    var readiness = 3
    private(set) var picked: [String] = []
    /// Slutskærmen efter finish(). nil = ingen.
    var adjustments: [Adjustment]?
    private(set) var toastMessage: String?
    private var toastTask: Task<Void, Never>?

    let timer = RestTimer()

    private static let activeKey = "treg_active"

    init(context: ModelContext) {
        self.context = context
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let s = existing.first {
            settings = s
        } else {
            let s = AppSettings()
            context.insert(s)
            settings = s
        }
        load()
    }

    // MARK: - lager

    private func load() {
        customEx = [:]
        for c in (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [] {
            customEx[c.id] = c.def
        }
        progress = [:]
        for p in (try? context.fetch(FetchDescriptor<ExerciseProgress>())) ?? [] {
            progress[p.id] = p
        }
        let byTs = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\WorkoutLog.ts)])
        log = (try? context.fetch(byTs)) ?? []

        // migrate(): fjern ukendte id'er fra grupperne og sørg for, at alle grupper findes.
        var g = settings.groups
        for t in Catalog.tg {
            g[t] = (g[t] ?? []).filter { EX($0) != nil }
        }
        settings.setGroups(g)
        settings.v = 3
        groups = g
        favs = settings.favs

        if let data = UserDefaults.standard.data(forKey: Self.activeKey),
           var a = try? JSONDecoder().decode(ActiveSession.self, from: data) {
            a.ex = a.ex.filter { EX($0.id) != nil }
            active = a
        }
        save()
    }

    private func save() {
        try? context.save()
    }

    private func saveActive() {
        if let active, let data = try? JSONEncoder().encode(active) {
            UserDefaults.standard.set(data, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }

    // MARK: - øvelser

    /// EX = BUILTIN_EX + D.customEx
    func EX(_ id: String) -> ExerciseDef? {
        Catalog.builtin[id] ?? customEx[id]
    }

    func name(_ id: String) -> String {
        EX(id)?.n ?? id
    }

    /// st(id): opretter progression for øvelsen, hvis den mangler.
    @discardableResult
    func st(_ id: String) -> ExerciseProgress {
        if let p = progress[id] { return p }
        let p = ExerciseProgress(id: id, w: nil, sets: EX(id)?.s ?? 3)
        context.insert(p)
        progress[id] = p
        return p
    }

    /// Antal sæt uden at oprette en progression (webappen opretter den blot i hukommelsen).
    func stSets(_ id: String) -> Int {
        progress[id]?.sets ?? EX(id)?.s ?? 0
    }

    func stall(_ id: String) -> Int {
        progress[id]?.stall ?? 0
    }

    func inc(_ id: String) -> Double {
        EX(id)?.t == "u" ? settings.incU : settings.incL
    }

    // MARK: - muskelgrupper

    func tgOf(_ id: String) -> String {
        let m = EX(id)?.m ?? ""
        return Catalog.tgMap[m] ?? m
    }

    func sortGroups(_ gs: [String]) -> [String] {
        gs.sorted { orderIndex($0) < orderIndex($1) }
    }

    private func orderIndex(_ g: String) -> Int {
        Catalog.sessionOrder.firstIndex(of: g) ?? -1
    }

    func groupsOfIds(_ ids: [String]) -> [String] {
        var gs: [String] = []
        for id in ids where EX(id) != nil {
            let g = tgOf(id)
            if !gs.contains(g) { gs.append(g) }
        }
        return sortGroups(gs)
    }

    func lastTrained() -> [String: Double] {
        var m: [String: Double] = [:]
        for l in log {
            for g in l.groups {
                if m[g] == nil || l.ts > m[g]! { m[g] = l.ts }
            }
        }
        return m
    }

    func groupCount(_ g: String) -> Int {
        (groups[g] ?? []).count
    }

    func capFor(_ g: String, _ n: Int) -> Int {
        if n == 1 { return 99 }
        let isBig = Catalog.big.contains(g)
        return n == 2 ? (isBig ? 4 : 3) : (isBig ? 3 : 2)
    }

    func pickFor(_ gs: [String]) -> [String] {
        var ids: [String] = []
        let n = gs.count
        for g in sortGroups(gs) {
            for id in (groups[g] ?? []).prefix(capFor(g, n)) {
                if EX(id) != nil && !ids.contains(id) { ids.append(id) }
            }
        }
        return ids
    }

    func setsFor(_ ids: [String]) -> Int {
        ids.reduce(0) { $0 + stSets($1) }
    }

    func recommend() -> (groups: [String], last: Double) {
        let last = lastTrained()
        let now = nowMs()
        var best: [String]?
        var score = -1.0
        for p in Catalog.pairs {
            let gs = p.filter { groupCount($0) > 0 }
            if gs.isEmpty { continue }
            let s = gs.map { g in last[g].map { now - $0 } ?? Double.infinity }.min()!
            if s > score {
                score = s
                best = gs
            }
        }
        let result = best ?? Array(Catalog.tg.filter { groupCount($0) > 0 }.prefix(1))
        var lastTs = 0.0
        for g in result {
            if let t = last[g], t > lastTs { lastTs = t }
        }
        return (result, lastTs)
    }

    // MARK: - datoer

    func nowMs() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded(.down)
    }

    private func dayStart(_ ms: Double) -> Double {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ms / 1000)).timeIntervalSince1970 * 1000
    }

    func daysAgo(_ ts: Double) -> Int {
        Int(((dayStart(nowMs()) - dayStart(ts)) / 86_400_000 + 0.5).rounded(.down))
    }

    func agoTxt(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "ikke endnu" }
        let d = daysAgo(ts)
        return d <= 0 ? "i dag" : d == 1 ? "i går" : "\(d) dage siden"
    }

    func restTxt(_ ts: Double) -> String {
        if ts <= 0 { return "ikke trænet endnu" }
        let d = daysAgo(ts)
        return d <= 0 ? "trænet i dag" : "hvilet \(d)" + (d == 1 ? " dag" : " dage")
    }

    // MARK: - forside

    func stalled() -> Int {
        progress.values.filter { $0.stall >= 1 }.count
    }

    var showDeload: Bool {
        log.count - settings.deload >= 18 || stalled() >= 3
    }

    func togglePick(_ g: String) {
        if let i = picked.firstIndex(of: g) {
            picked.remove(at: i)
        } else {
            if picked.count >= 3 {
                toast("Vælg højst 3 muskelgrupper ad gangen.")
                return
            }
            picked.append(g)
        }
    }

    func useFav(_ i: Int) {
        guard favs.indices.contains(i) else { return }
        picked = favs[i].filter { groupCount($0) > 0 }
    }

    func saveFav() {
        let gs = sortGroups(picked)
        favs.append(gs)
        settings.setFavs(favs)
        save()
        toast(gs.joined(separator: " + ") + " er gemt som favorit.")
    }

    func removeFav(_ i: Int) {
        guard favs.indices.contains(i) else { return }
        favs.remove(at: i)
        settings.setFavs(favs)
        save()
    }

    func isFav(_ gs: [String]) -> Bool {
        let key = gs.joined(separator: "+")
        return favs.contains { $0.joined(separator: "+") == key }
    }

    // MARK: - start af træning

    func makeSessionEx(_ id: String, _ rd: Int) -> ActiveExercise {
        let s = st(id)
        let n = max(2, s.sets - (rd == 1 ? 1 : 0))
        let target = s.w.map { rnd($0 * Catalog.readyMult(rd), inc(id) / 2) }
        return ActiveExercise(id: id, target: target, sets: Array(repeating: ActiveSet(), count: n))
    }

    func start(_ gs: [String]) {
        let ids = pickFor(gs)
        if ids.isEmpty {
            toast("Der er ingen øvelser i de valgte muskelgrupper.")
            return
        }
        active = ActiveSession(
            name: gs.joined(separator: " + "),
            groups: gs,
            readiness: readiness,
            ex: ids.map { makeSessionEx($0, readiness) }
        )
        saveActive()
        save()
    }

    func startRec() {
        start(recommend().groups)
    }

    func startPicked() {
        if picked.isEmpty { return }
        let gs = sortGroups(picked)
        picked = []
        start(gs)
    }

    // MARK: - under træning

    func setVal(_ i: Int, _ j: Int, _ k: WritableKeyPath<ActiveSet, String>, _ v: String) {
        guard var a = active, a.ex.indices.contains(i), a.ex[i].sets.indices.contains(j) else { return }
        a.ex[i].sets[j][keyPath: k] = v
        active = a
        saveActive()
    }

    func tick(_ i: Int, _ j: Int) {
        guard var a = active, a.ex.indices.contains(i), a.ex[i].sets.indices.contains(j) else { return }
        let e = a.ex[i]
        var s = e.sets[j]
        let x = EX(e.id)
        if !s.done {
            if s.w.isEmpty, let t = e.target { s.w = inputString(t) }
            if s.r.isEmpty && !s.w.isEmpty, let x { s.r = String(x.hi) }
            if s.rir.isEmpty { s.rir = "2" }
            s.done = true
            a.ex[i].sets[j] = s
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if j + 1 < e.sets.count && a.ex[i].sets[j + 1].w.isEmpty {
                a.ex[i].sets[j + 1].w = s.w
            }
            active = a
            saveActive()
            if let x { rest(x.r, after: (i, j)) }
        } else {
            a.ex[i].sets[j].done = false
            active = a
            saveActive()
        }
    }

    func addSet(_ i: Int) {
        guard var a = active, a.ex.indices.contains(i) else { return }
        a.ex[i].sets.append(ActiveSet())
        active = a
        saveActive()
    }

    func cancelSession() {
        active = nil
        saveActive()
        timer.stop()
    }

    /// Pause-knappen ved en øvelse (uden at et sæt er markeret færdigt).
    func manualRest(_ i: Int) {
        guard let a = active, a.ex.indices.contains(i), let x = EX(a.ex[i].id) else { return }
        let j = a.ex[i].sets.firstIndex { !$0.done }
        rest(x.r, after: j.map { (i, $0 - 1) } ?? (i, a.ex[i].sets.count - 1))
    }

    /// Starter hviletimeren. `after` er det sæt, man lige har taget; teksten viser det næste.
    private func rest(_ sec: Int, after: (Int, Int)) {
        guard let a = active else { return }
        let next = nextSetText(a, after: after)
        timer.start(seconds: sec, workout: a.name, title: next.title, detail: next.detail)
    }

    private func nextSetText(_ a: ActiveSession, after: (Int, Int)) -> (title: String, detail: String) {
        var i = after.0
        var j = after.1 + 1
        while a.ex.indices.contains(i) {
            let e = a.ex[i]
            while j < e.sets.count {
                if !e.sets[j].done {
                    let s = e.sets[j]
                    var detail = "Sæt \(j + 1) af \(e.sets.count)"
                    let w = num(s.w) ?? e.target
                    if let w { detail += " · \(fmt(w)) kg" }
                    if let x = EX(e.id) { detail += " · \(x.lo)–\(x.hi)" }
                    return (name(e.id), detail)
                }
                j += 1
            }
            i += 1
            j = 0
        }
        return ("Sidste sæt er taget", "Afslut træningen, når du er klar")
    }

    /// Talværdi som den skal stå i et inputfelt.
    private func inputString(_ v: Double) -> String {
        fmt(v)
    }

    // MARK: - afslutning og progression

    func finish() {
        guard let a = active else { return }
        var adj: [Adjustment] = []
        var entries: [LogEntry] = []
        for e in a.ex {
            guard let x = EX(e.id) else { continue }
            let s = st(e.id)
            let step = inc(e.id)
            // Kun sæt med vægt og reps > 0. "i tanken" = 2, hvis tom.
            let sets: [LogSet] = e.sets.compactMap { v in
                guard let w = num(v.w), let r = num(v.r), r > 0 else { return nil }
                return LogSet(w: w, r: r, rir: num(v.rir) ?? 2)
            }
            entries.append(LogEntry(ex: e.id, sets: sets))
            if sets.isEmpty { continue }
            let minR = sets.map(\.r).min()!
            let top = sets.map(\.w).max()!
            let lastRir = sets[sets.count - 1].rir
            let old = s.w
            let hi = Double(x.hi)
            let lo = Double(x.lo)
            var msg = ""
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
            if s.wins >= 3 && s.sets < x.s + 2 && a.readiness >= 4 {
                s.sets += 1; s.wins = 0; msg += ", plus ét sæt"
            }
            adj.append(Adjustment(n: x.n, from: old, to: s.w ?? top, msg: msg))
        }
        let trained = groupsOfIds(entries.filter { !$0.sets.isEmpty }.map(\.ex))
        let d = Date()
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        let date = String(format: "%02d.%02d.%d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
        let entry = WorkoutLog(
            name: a.name,
            groups: trained.isEmpty ? a.groups : trained,
            date: date,
            ts: nowMs(),
            readiness: a.readiness,
            entries: entries
        )
        context.insert(entry)
        log.append(entry)
        save()
        active = nil
        saveActive()
        timer.stop()
        adjustments = adj
    }

    func doDeload() {
        for (k, s) in progress {
            guard let x = EX(k) else { continue }
            if let w = s.w, w != 0 { s.w = rnd(w * 0.9, inc(k) / 2) }
            s.stall = 0
            s.wins = 0
            s.sets = x.s
        }
        settings.deload = log.count
        save()
    }

    // MARK: - toast

    func toast(_ msg: String) {
        toastMessage = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if Task.isCancelled { return }
            self?.toastMessage = nil
        }
    }
}
