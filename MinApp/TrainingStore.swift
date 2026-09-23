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

/// En række fra exStats(id).
struct StatRow: Hashable {
    var date: String
    var best: LogSet
    var e1: Double
    var top: Double
    var vol: Double
    var sets: Int
}

/// Et sæt i den aktive træning.
struct SetRef: Hashable {
    var i: Int
    var j: Int
}

enum Tab: String {
    case home, hist, set
}

/// Port af webappens logik (afsnit 3–5 i docs/traeningsapp-kontekst.md og docs/webapp.html).
/// Funktionsnavnene svarer til webappens, så de kan sammenlignes linje for linje.
@MainActor
@Observable
final class TrainingStore {
    private let context: ModelContext
    private(set) var settings: AppSettings
    private var progress: [String: ExerciseProgress] = [:]
    /// D.log i rækkefølge.
    private(set) var log: [LogRecord] = []
    private var customEx: [String: ExerciseDef] = [:]

    /// D.groups og D.favs, spejlet fra settings.
    private(set) var groups: [String: [String]] = [:]
    private(set) var favs: [[String]] = []

    private(set) var active: ActiveSession?
    var tab: Tab = .home
    var readiness = 3
    private(set) var picked: [String] = []
    /// Slutskærmen efter finish(). nil = ingen.
    var adjustments: [Adjustment]?
    private(set) var toastMessage: String?
    private var toastTask: Task<Void, Never>?
    /// Det sæt, Live Activity viser som det næste ("Sæt færdigt").
    @ObservationIgnored private var nextRef: SetRef?

    let timer = RestTimer()

    private static let activeKey = "treg_active"
    private static let quickKey = "treg_quick_w"

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
        log = ((try? context.fetch(byTs)) ?? []).map(\.record)

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
        } else {
            active = nil
        }
        save()
    }

    private func save() {
        try? context.save()
    }

    private func saveGroups() {
        settings.setGroups(groups)
        save()
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

    /// Object.keys(EX): indbyggede i webappens rækkefølge, derefter egne i oprettelsesrækkefølge.
    var exKeys: [String] {
        Catalog.builtinList.map(\.id) + customEx.keys.sorted()
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

    func stW(_ id: String) -> Double? {
        progress[id]?.w
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

    /// byGroupOrder: sortering efter TG (stabil, som Array.sort i JS).
    func byGroupOrder(_ ids: [String]) -> [String] {
        stableSorted(ids) { tgIndex(tgOf($0)) }
    }

    private func tgIndex(_ g: String) -> Int {
        Catalog.tg.firstIndex(of: g) ?? -1
    }

    private func stableSorted(_ ids: [String], key: (String) -> Int) -> [String] {
        ids.enumerated()
            .sorted { a, b in
                let ka = key(a.element), kb = key(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
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

    func groupList(_ g: String) -> [String] {
        groups[g] ?? []
    }

    func groupCount(_ g: String) -> Int {
        groupList(g).count
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
            for id in groupList(g).prefix(capFor(g, n)) {
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
        Int(jsRound((dayStart(nowMs()) - dayStart(ts)) / 86_400_000))
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
        var a = ActiveSession(
            name: gs.joined(separator: " + "),
            groups: gs,
            readiness: readiness,
            ex: ids.map { makeSessionEx($0, readiness) }
        )
        if let pending = consumePendingQuick(), !a.ex.isEmpty, !a.ex[0].sets.isEmpty {
            a.ex[0].sets[0].w = fmt(pending)
        }
        active = a
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
            if s.w.isEmpty, let t = e.target { s.w = fmt(t) }
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
            if let x { rest(x.r, after: SetRef(i: i, j: j)) }
        } else {
            a.ex[i].sets[j].done = false
            active = a
            saveActive()
        }
    }

    /// "Sæt færdigt" fra Live Activity: markerer det sæt, der vises som det næste.
    func completeNextSet() {
        guard let a = active else { return }
        if let r = nextRef, a.ex.indices.contains(r.i), a.ex[r.i].sets.indices.contains(r.j),
           !a.ex[r.i].sets[r.j].done {
            tick(r.i, r.j)
            return
        }
        for (i, e) in a.ex.enumerated() {
            if let j = e.sets.firstIndex(where: { !$0.done }) {
                tick(i, j)
                return
            }
        }
    }

    func addSet(_ i: Int) {
        guard var a = active, a.ex.indices.contains(i) else { return }
        a.ex[i].sets.append(ActiveSet())
        active = a
        saveActive()
    }

    /// Om der er logget noget på øvelsen (removeFromSession spørger så først).
    func hasLogged(_ i: Int) -> Bool {
        guard let a = active, a.ex.indices.contains(i) else { return false }
        return a.ex[i].sets.contains { $0.done || !$0.w.isEmpty || !$0.r.isEmpty }
    }

    func removeFromSession(_ i: Int) {
        guard var a = active, a.ex.indices.contains(i) else { return }
        let id = a.ex[i].id
        a.ex.remove(at: i)
        active = a
        saveActive()
        toast(name(id) + " er fjernet fra dagens træning.")
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
        rest(x.r, after: SetRef(i: i, j: (j ?? a.ex[i].sets.count) - 1))
    }

    /// Starter hviletimeren. `after` er det sæt, man lige har taget; teksten viser det næste.
    private func rest(_ sec: Int, after: SetRef) {
        guard let a = active else { return }
        let next = nextSet(a, after: after)
        nextRef = next?.ref
        timer.start(
            seconds: sec,
            workout: a.name,
            title: next?.title ?? "Sidste sæt er taget",
            detail: next?.detail ?? "Afslut træningen, når du er klar"
        )
    }

    private func nextSet(_ a: ActiveSession, after: SetRef) -> (ref: SetRef, title: String, detail: String)? {
        var i = after.i
        var j = after.j + 1
        while a.ex.indices.contains(i) {
            let e = a.ex[i]
            while j < e.sets.count {
                if !e.sets[j].done {
                    let s = e.sets[j]
                    var detail = "Sæt \(j + 1) af \(e.sets.count)"
                    if let w = num(s.w) ?? e.target { detail += " · \(fmt(w)) kg" }
                    if let x = EX(e.id) { detail += " · \(x.lo)–\(x.hi)" }
                    return (SetRef(i: i, j: j), name(e.id), detail)
                }
                j += 1
            }
            i += 1
            j = 0
        }
        return nil
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
        let rec = LogRecord(
            name: a.name,
            groups: trained.isEmpty ? a.groups : trained,
            date: Self.dateString(Date()),
            ts: nowMs(),
            readiness: a.readiness,
            entries: entries
        )
        insertLog(rec)
        log.append(rec)
        save()
        active = nil
        saveActive()
        timer.stop()
        adjustments = adj
    }

    private func insertLog(_ r: LogRecord) {
        context.insert(WorkoutLog(
            name: r.name, groups: r.groups, date: r.date, ts: r.ts, readiness: r.readiness, entries: r.entries
        ))
    }

    static func dateString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        return String(format: "%02ld.%02ld.%ld", c.day ?? 0, c.month ?? 0, c.year ?? 0)
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

    // MARK: - byt / tilføj øvelse

    func doSwap(old: String, new nid: String, inSession: Bool) {
        if nid == old { return }
        for g in Catalog.tg {
            var L = groupList(g)
            guard let i = L.firstIndex(of: old) else { continue }
            if L.contains(nid) { L.remove(at: i) } else { L[i] = nid }
            groups[g] = L
        }
        saveGroups()
        if inSession, var a = active {
            for (i, e) in a.ex.enumerated() where e.id == old {
                a.ex[i] = makeSessionEx(nid, a.readiness)
            }
            active = a
            saveActive()
            save()
        }
    }

    /// pickAdd(k) for mode "group".
    func addToGroup(_ id: String, _ g: String) {
        var L = groupList(g)
        if !L.contains(id) { L.append(id) }
        groups[g] = L
        saveGroups()
        toast(name(id) + " er lagt i " + g + ".")
    }

    /// pickAdd(k) for mode "session".
    func addToSession(_ id: String) {
        guard var a = active else { return }
        a.ex.append(makeSessionEx(id, a.readiness))
        active = a
        saveActive()
        save()
        toast(name(id) + " er lagt til dagens træning.")
    }

    /// Fokusgrupper i openPicker("session").
    var sessionFocus: [String] {
        guard let a = active else { return [] }
        return a.groups.isEmpty ? groupsOfIds(a.ex.map(\.id)) : a.groups
    }

    // MARK: - egne øvelser

    struct NewExercise {
        var name: String
        var group: String
        var lo: String
        var hi: String
        var sets: String
        var rest: String
        var desc: String
    }

    /// doCreate(). Returnerer false, hvis navnet mangler.
    @discardableResult
    func doCreate(_ f: NewExercise, toSession: Bool) -> Bool {
        let name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            toast("Giv øvelsen et navn.")
            return false
        }
        let g = f.group
        // Number(v)||d: tom, 0 og ugyldig giver standardværdien.
        func orDefault(_ s: String, _ d: Double) -> Double {
            let v = num(s) ?? 0
            return v == 0 || v.isNaN ? d : v
        }
        var lo = max(1, Int(jsRound(orDefault(f.lo, 8))))
        var hi = max(1, Int(jsRound(orDefault(f.hi, 12))))
        if lo > hi { swap(&lo, &hi) }
        let sets = min(8, max(1, Int(jsRound(orDefault(f.sets, 3)))))
        let rest = max(15, Int(jsRound(orDefault(f.rest, 90))))
        let id = "custom_" + String(Int(nowMs()), radix: 36)
        let def = ExerciseDef(
            id: id, n: name, m: g, t: g == "Ben" ? "l" : "u", lo: lo, hi: hi, s: sets, r: rest,
            d: f.desc.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(CustomExercise(
            id: id, n: def.n, m: def.m, t: def.t, lo: lo, hi: hi, s: sets, r: rest, d: def.d ?? ""
        ))
        customEx[id] = def
        var L = groupList(g)
        L.append(id)
        groups[g] = L
        let intoSession = toSession && active != nil
        if intoSession, var a = active {
            a.ex.append(makeSessionEx(id, a.readiness))
            active = a
            saveActive()
        }
        saveGroups()
        toast(name + (intoSession ? " er oprettet og lagt til dagens træning." : " er oprettet og lagt i " + g + "."))
        return true
    }

    // MARK: - program

    func moveEx(_ g: String, _ i: Int) {
        var L = groupList(g)
        guard i >= 1, i < L.count else { return }
        L.swapAt(i - 1, i)
        groups[g] = L
        saveGroups()
    }

    func removeFromGroup(_ g: String, _ i: Int) {
        var L = groupList(g)
        guard L.indices.contains(i) else { return }
        let id = L.remove(at: i)
        groups[g] = L
        saveGroups()
        toast(name(id) + " er fjernet fra " + g + ".")
    }

    /// oninput="D.inc.u=Number(this.value)||2.5"
    func setInc(upper: Bool, _ text: String) {
        let v = num(text) ?? 0
        if upper {
            settings.incU = v == 0 ? 2.5 : v
        } else {
            settings.incL = v == 0 ? 5 : v
        }
        save()
    }

    // MARK: - udvikling

    func exStats(_ id: String) -> [StatRow] {
        var rows: [StatRow] = []
        for l in log {
            for e in l.entries where e.ex == id && !e.sets.isEmpty {
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
                rows.append(StatRow(date: l.date, best: best, e1: be, top: top, vol: vol, sets: e.sets.count))
            }
        }
        return rows
    }

    static func volume(_ l: LogRecord) -> Double {
        l.entries.reduce(0) { a, e in a + e.sets.reduce(0) { $0 + $1.w * $1.r } }
    }

    static func setCount(_ l: LogRecord) -> Int {
        l.entries.reduce(0) { $0 + $1.sets.count }
    }

    // MARK: - backup

    /// JSON.stringify(D)
    func exportData() -> Data {
        var ex: [String: Any] = [:]
        for (id, p) in progress {
            var item: [String: Any] = ["sets": p.sets, "stall": p.stall, "wins": p.wins]
            if let w = p.w {
                item["w"] = w
            } else {
                item["w"] = NSNull()
            }
            ex[id] = item
        }

        var logArr: [Any] = []
        for l in log {
            var entries: [Any] = []
            for e in l.entries {
                var sets: [Any] = []
                for x in e.sets {
                    let set: [String: Any] = ["w": x.w, "r": x.r, "rir": x.rir]
                    sets.append(set)
                }
                let entry: [String: Any] = ["ex": e.ex, "sets": sets]
                entries.append(entry)
            }
            var item: [String: Any] = [:]
            item["name"] = l.name
            item["groups"] = l.groups
            item["date"] = l.date
            item["ts"] = Int64(l.ts)
            item["readiness"] = l.readiness
            item["entries"] = entries
            logArr.append(item)
        }

        var custom: [String: Any] = [:]
        for (id, c) in customEx {
            var item: [String: Any] = [:]
            item["n"] = c.n
            item["m"] = c.m
            item["t"] = c.t
            item["lo"] = c.lo
            item["hi"] = c.hi
            item["s"] = c.s
            item["r"] = c.r
            item["d"] = c.d ?? ""
            custom[id] = item
        }

        var d: [String: Any] = [:]
        d["v"] = 3
        d["groups"] = groups
        d["inc"] = ["u": settings.incU, "l": settings.incL]
        d["ex"] = ex
        d["log"] = logArr
        d["deload"] = settings.deload
        d["customEx"] = custom
        d["favs"] = favs
        return (try? JSONSerialization.data(withJSONObject: d, options: [.withoutEscapingSlashes])) ?? Data()
    }

    /// Erstatter alle data med backuppen (doImport efter bekræftelse).
    func applyBackup(_ b: BackupData) {
        replaceAll(with: b)
        toast("Backup gendannet.")
    }

    /// wipe(): D=migrate(fresh()), active=null, picked=[].
    func wipe() {
        replaceAll(with: BackupData(
            groups: Catalog.defaultGroups, incU: 2.5, incL: 5, ex: [:], log: [], deload: 0, customEx: [], favs: []
        ))
        active = nil
        picked = []
        saveActive()
        timer.stop()
        toast("Alt er slettet.")
    }

    private func replaceAll(with b: BackupData) {
        for m in (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? [] { context.delete(m) }
        for m in (try? context.fetch(FetchDescriptor<ExerciseProgress>())) ?? [] { context.delete(m) }
        for m in (try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [] { context.delete(m) }
        save()

        customEx = [:]
        for c in b.customEx {
            customEx[c.id] = c
            context.insert(CustomExercise(
                id: c.id, n: c.n, m: c.m, t: c.t, lo: c.lo, hi: c.hi, s: c.s, r: c.r, d: c.d ?? ""
            ))
        }
        progress = [:]
        for (id, p) in b.ex {
            let m = ExerciseProgress(
                id: id, w: p.w, sets: p.sets ?? EX(id)?.s ?? 3, stall: p.stall, wins: p.wins
            )
            context.insert(m)
            progress[id] = m
        }
        log = b.log.map { l in
            // logGroups(l): gamle logposter uden groups får grupper udledt af øvelserne.
            let gs = l.groups ?? groupsOfIds(l.entries.filter { !$0.sets.isEmpty }.map(\.ex))
            return LogRecord(name: l.name, groups: gs, date: l.date, ts: l.ts, readiness: l.readiness, entries: l.entries)
        }
        for r in log { insertLog(r) }

        groups = b.groups
        favs = b.favs
        settings.setGroups(groups)
        settings.setFavs(favs)
        settings.incU = b.incU
        settings.incL = b.incL
        settings.deload = b.deload
        settings.v = 3

        if var a = active {
            a.ex = a.ex.filter { EX($0.id) != nil }
            active = a
            saveActive()
        }
        save()
    }

    // MARK: - lynindtastning fra genvej (minapp://?w=72,5)

    func consumePendingQuick() -> Double? {
        guard let raw = UserDefaults.standard.string(forKey: Self.quickKey), !raw.isEmpty else { return nil }
        UserDefaults.standard.set("", forKey: Self.quickKey)
        return Double(raw)
    }

    /// applyQuickParam()
    func applyQuick(_ url: URL) {
        guard let w = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "w" })?.value,
            let n = num(w) else { return }
        if var a = active {
            var applied = false
            for i in a.ex.indices {
                for j in a.ex[i].sets.indices where !applied && !a.ex[i].sets[j].done {
                    a.ex[i].sets[j].w = fmt(n)
                    applied = true
                }
            }
            if applied {
                active = a
                saveActive()
                toast(fmt(n) + " kg sat ind i næste sæt.")
            } else {
                toast(fmt(n) + " kg — alle sæt er allerede udfyldt.")
            }
        } else {
            UserDefaults.standard.set(String(n), forKey: Self.quickKey)
            toast(fmt(n) + " kg gemt. Start en træning for at bruge det.")
        }
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
