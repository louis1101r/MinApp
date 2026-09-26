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

/// Slutskærmens justeringer for én person.
struct FinishGroup: Identifiable, Hashable {
    var profile: Profile
    var name: String
    var items: [Adjustment]
    var id: String { profile.rawValue }
}

/// Et sæt i den aktive træning.
struct SetRef: Hashable {
    var i: Int
    var j: Int
}

enum Tab: String {
    case home, hist, set
}

/// Port af webappens logik (afsnit 3–5 i docs/traeningsapp-kontekst.md og docs/webapp.html),
/// udvidet med træningsmakker. Den rene logik ligger i Logic.swift og testes lokalt.
@MainActor
@Observable
final class TrainingStore {
    private let container: ModelContainer
    private let context: ModelContext
    private(set) var settings: AppSettings
    private var progress: [Profile: [String: ProfileProgress]] = [.louis: [:], .buddy: [:]]
    /// D.log per profil (fuld, til backup). Indlæses i baggrunden.
    private var logs: [Profile: [LogRecord]] = [.louis: [], .buddy: []]
    /// Cache over loggen per profil.
    private(set) var index: [Profile: ProfileIndex] = [.louis: ProfileIndex(), .buddy: ProfileIndex()]
    private(set) var isLoaded = false
    private var customEx: [String: ExerciseDef] = [:]

    /// D.groups og D.favs (fælles).
    private(set) var groups: [String: [String]] = [:]
    private(set) var favs: [[String]] = []

    private(set) var active: ActiveSession?
    var tab: Tab = .home
    /// Dagsform per person på forsiden.
    var readiness: [Profile: Int] = [.louis: 3, .buddy: 3]
    /// "Træn sammen" valgt på forsiden.
    var together = false
    /// Valgt profil i Udvikling.
    var histProfile: Profile = .louis
    private(set) var picked: [String] = []
    /// Slutskærmen efter finish(). nil = ingen.
    var finishGroups: [FinishGroup]?
    private(set) var toastMessage: String?
    private var toastTask: Task<Void, Never>?
    /// Det sæt per person, Live Activity viser som det næste ("Sæt færdigt").
    @ObservationIgnored private var nextRef: [Profile: SetRef] = [:]

    let timers = RestTimers()

    private static let activeKey = "treg_active_v2"
    private static let legacyActiveKey = "treg_active"
    private static let quickKey = "treg_quick_w"

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
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

        if settings.v < 4 {
            migrateToV4()
        }

        progress = [.louis: [:], .buddy: [:]]
        for p in (try? context.fetch(FetchDescriptor<ProfileProgress>())) ?? [] {
            progress[Profile(rawValue: p.profile) ?? .louis, default: [:]][p.ex] = p
        }

        // migrate(): fjern ukendte id'er fra grupperne og sørg for, at alle grupper findes.
        var g = settings.groups
        for t in Catalog.tg {
            g[t] = (g[t] ?? []).filter { EX($0) != nil }
        }
        settings.setGroups(g)
        groups = g
        favs = settings.favs

        loadActive()
        save()
        loadLogsInBackground()
    }

    /// v3 → v4: gem en kopi af alle data, flyt Louis' progression til den nye tabel.
    /// (Loggen har fået feltet profile = "louis" af SwiftData ved åbningen.)
    private func migrateToV4() {
        let old = (try? context.fetch(FetchDescriptor<ExerciseProgress>())) ?? []
        var ex: [String: ProgressValues] = [:]
        for o in old {
            ex[o.id] = ProgressValues(w: o.w, sets: o.sets, stall: o.stall, wins: o.wins)
        }
        let byTs = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\WorkoutLog.ts)])
        let log = ((try? context.fetch(byTs)) ?? []).map(\.record)
        let before = BackupData(
            sourceVersion: 3,
            groups: settings.groups,
            incU: settings.incU,
            incL: settings.incL,
            customEx: customEx.values.sorted { $0.id < $1.id },
            favs: settings.favs,
            louis: ProfileData(name: "Louis", ex: ex, log: log, deload: settings.deload),
            buddy: nil
        )
        BackupFiles.writeOnce(Backup.serialize(before, version: 3), name: BackupFiles.preMigrationName)

        for (id, v) in ex {
            context.insert(ProfileProgress(profile: .louis, ex: id, values: v))
        }
        for o in old { context.delete(o) }
        settings.v = 4
        save()
    }

    private func loadLogsInBackground() {
        let loader = LogLoader(modelContainer: container)
        Task {
            let result = await loader.load()
            self.logs = result.logs
            self.index = result.index
            self.isLoaded = true
            self.weeklyBackupIfDue()
        }
    }

    private func save() {
        try? context.save()
    }

    private func saveGroups() {
        settings.setGroups(groups)
        save()
    }

    private func loadActive() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.activeKey),
           let a = try? JSONDecoder().decode(ActiveSession.self, from: data) {
            active = a
        } else if let data = defaults.data(forKey: Self.legacyActiveKey),
                  let old = try? JSONDecoder().decode(LegacyActiveSession.self, from: data) {
            active = old.converted
        } else {
            active = nil
        }
        defaults.removeObject(forKey: Self.legacyActiveKey)
        if var a = active {
            a.ex = a.ex.filter { EX($0.id) != nil }
            active = a
        }
        saveActive()
    }

    private func saveActive() {
        if let active, let data = try? JSONEncoder().encode(active) {
            UserDefaults.standard.set(data, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }

    // MARK: - profiler

    func name(of p: Profile) -> String {
        p == .louis ? "Louis" : settings.buddyName
    }

    func setBuddyName(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.buddyName = t.isEmpty ? "Makker" : String(t.prefix(30))
        save()
    }

    func logCount(_ p: Profile) -> Int {
        index[p]?.count ?? 0
    }

    func ix(_ p: Profile) -> ProfileIndex {
        index[p] ?? ProfileIndex()
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
    private func st(_ p: Profile, _ id: String) -> ProfileProgress {
        if let s = progress[p]?[id] { return s }
        let s = ProfileProgress(profile: p, ex: id, values: ProgressValues(w: nil, sets: EX(id)?.s ?? 3, stall: 0, wins: 0))
        context.insert(s)
        progress[p, default: [:]][id] = s
        return s
    }

    /// Antal sæt uden at oprette en progression.
    func stSets(_ id: String, _ p: Profile = .louis) -> Int {
        progress[p]?[id]?.sets ?? EX(id)?.s ?? 0
    }

    func stW(_ id: String, _ p: Profile = .louis) -> Double? {
        progress[p]?[id]?.w
    }

    func stall(_ id: String, _ p: Profile = .louis) -> Int {
        progress[p]?[id]?.stall ?? 0
    }

    func inc(_ id: String) -> Double {
        EX(id)?.t == "u" ? settings.incU : settings.incL
    }

    // MARK: - muskelgrupper

    private var exLookup: ExLookup {
        let builtin = Catalog.builtin
        let custom = customEx
        return { builtin[$0] ?? custom[$0] }
    }

    func tgOf(_ id: String) -> String {
        Logic.tgOf(id, exLookup)
    }

    func sortGroups(_ gs: [String]) -> [String] {
        Logic.sortGroups(gs)
    }

    /// byGroupOrder: sortering efter TG (stabil, som Array.sort i JS).
    func byGroupOrder(_ ids: [String]) -> [String] {
        let look = exLookup
        func key(_ id: String) -> Int { Catalog.tg.firstIndex(of: Logic.tgOf(id, look)) ?? -1 }
        return ids.enumerated()
            .sorted { a, b in
                let ka = key(a.element), kb = key(b.element)
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
    }

    func groupsOfIds(_ ids: [String]) -> [String] {
        Logic.groupsOfIds(ids, exLookup)
    }

    func lastTrained(_ p: Profile = .louis) -> [String: Double] {
        ix(p).lastTrained
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

    /// Anbefalingen bygger altid på Louis.
    func recommend() -> (groups: [String], last: Double) {
        let last = lastTrained(.louis)
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

    func stalled(_ p: Profile) -> Int {
        (progress[p] ?? [:]).values.filter { $0.stall >= 1 }.count
    }

    func showDeload(_ p: Profile) -> Bool {
        logCount(p) - settings.deload(p) >= 18 || stalled(p) >= 3
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

    /// makeSessionEx(id): en del per person med egen målvægt fra egen progression.
    private func makeSessionEx(_ id: String, _ a: ActiveSession) -> ActiveExercise {
        var e = ActiveExercise(id: id, people: [:])
        for p in a.profiles {
            e[p] = Logic.sessionPerson(st(p, id).values, readiness: a.readiness(p), inc: inc(id))
        }
        return e
    }

    func start(_ gs: [String]) {
        let ids = pickFor(gs)
        if ids.isEmpty {
            toast("Der er ingen øvelser i de valgte muskelgrupper.")
            return
        }
        let profiles: [Profile] = together ? [.louis, .buddy] : [.louis]
        var rd: [String: Int] = [:]
        for p in profiles { rd[p.rawValue] = readiness[p] ?? 3 }
        var a = ActiveSession(name: gs.joined(separator: " + "), groups: gs, profiles: profiles, readiness: rd, ex: [])
        a.ex = ids.map { makeSessionEx($0, a) }
        if let pending = consumePendingQuick(), !a.ex.isEmpty, var louis = a.ex[0][.louis], !louis.sets.isEmpty {
            louis.sets[0].w = fmt(pending)
            a.ex[0][.louis] = louis
        }
        active = a
        nextRef = [:]
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

    func value(_ i: Int, _ p: Profile, _ j: Int, _ k: KeyPath<ActiveSet, String>) -> String {
        guard let a = active, a.ex.indices.contains(i), let person = a.ex[i][p],
              person.sets.indices.contains(j) else { return "" }
        return person.sets[j][keyPath: k]
    }

    func setVal(_ i: Int, _ p: Profile, _ j: Int, _ k: WritableKeyPath<ActiveSet, String>, _ v: String) {
        guard var a = active, a.ex.indices.contains(i), var person = a.ex[i][p],
              person.sets.indices.contains(j) else { return }
        person.sets[j][keyPath: k] = v
        a.ex[i][p] = person
        active = a
        saveActive()
    }

    /// tick(i, j) for én person.
    func tick(_ i: Int, _ p: Profile, _ j: Int) {
        guard var a = active, a.ex.indices.contains(i), var person = a.ex[i][p],
              person.sets.indices.contains(j) else { return }
        let id = a.ex[i].id
        let x = EX(id)
        var s = person.sets[j]
        if !s.done {
            if s.w.isEmpty, let t = person.target { s.w = fmt(t) }
            if s.r.isEmpty && !s.w.isEmpty, let x { s.r = String(x.hi) }
            if s.rir.isEmpty { s.rir = "2" }
            s.done = true
            person.sets[j] = s
            if j + 1 < person.sets.count && person.sets[j + 1].w.isEmpty {
                person.sets[j + 1].w = s.w
            }
            a.ex[i][p] = person
            active = a
            saveActive()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let last = s.w.isEmpty ? "" : s.w + " × " + (s.r.isEmpty ? "–" : s.r)
            if let x { rest(p, x.r, after: SetRef(i: i, j: j), last: last) }
        } else {
            person.sets[j].done = false
            a.ex[i][p] = person
            active = a
            saveActive()
        }
    }

    /// "Sæt færdigt" fra Live Activity: markerer det sæt, der vises som personens næste.
    func completeNextSet(_ p: Profile) {
        guard let a = active, a.profiles.contains(p) else { return }
        if let r = nextRef[p], a.ex.indices.contains(r.i), let person = a.ex[r.i][p],
           person.sets.indices.contains(r.j), !person.sets[r.j].done {
            tick(r.i, p, r.j)
            return
        }
        for (i, e) in a.ex.enumerated() {
            if let j = e[p]?.sets.firstIndex(where: { !$0.done }) {
                tick(i, p, j)
                return
            }
        }
    }

    /// Ekstra sæt: ét til hver person.
    func addSet(_ i: Int) {
        guard var a = active, a.ex.indices.contains(i) else { return }
        for p in a.profiles {
            a.ex[i][p]?.sets.append(ActiveSet())
        }
        active = a
        saveActive()
    }

    /// Om der er logget noget på øvelsen (removeFromSession spørger så først).
    func hasLogged(_ i: Int) -> Bool {
        guard let a = active, a.ex.indices.contains(i) else { return false }
        return a.ex[i].people.values.contains { person in
            person.sets.contains { $0.done || !$0.w.isEmpty || !$0.r.isEmpty }
        }
    }

    func removeFromSession(_ i: Int) {
        guard var a = active, a.ex.indices.contains(i) else { return }
        let id = a.ex[i].id
        a.ex.remove(at: i)
        active = a
        nextRef = [:]
        saveActive()
        toast(name(id) + " er fjernet fra dagens træning.")
    }

    func cancelSession() {
        active = nil
        nextRef = [:]
        saveActive()
        timers.stopAll()
    }

    /// Pause-knappen ved en øvelse: starter pausen for alle i træningen.
    func manualRest(_ i: Int) {
        guard let a = active, a.ex.indices.contains(i), let x = EX(a.ex[i].id) else { return }
        for p in a.profiles {
            guard let person = a.ex[i][p] else { continue }
            let j = person.sets.firstIndex { !$0.done }
            rest(p, x.r, after: SetRef(i: i, j: (j ?? person.sets.count) - 1), last: nil)
        }
    }

    /// Starter personens hviletimer. `after` er det sæt, personen lige har taget.
    private func rest(_ p: Profile, _ sec: Int, after: SetRef, last: String?) {
        guard let a = active else { return }
        let next = nextSet(a, p, after: after)
        nextRef[p] = next?.ref
        timers.start(
            p,
            seconds: sec,
            workout: a.name,
            people: a.profiles.map { ($0, name(of: $0)) },
            title: next?.title ?? "Sidste sæt er taget",
            detail: next?.detail ?? "Afslut træningen, når du er klar",
            last: last
        )
    }

    private func nextSet(_ a: ActiveSession, _ p: Profile, after: SetRef) -> (ref: SetRef, title: String, detail: String)? {
        var i = after.i
        var j = after.j + 1
        while a.ex.indices.contains(i) {
            let e = a.ex[i]
            if let person = e[p] {
                while j < person.sets.count {
                    if !person.sets[j].done {
                        let s = person.sets[j]
                        var detail = "Sæt \(j + 1) af \(person.sets.count)"
                        if let w = num(s.w) ?? person.target { detail += " · \(fmt(w)) kg" }
                        if let x = EX(e.id) { detail += " · \(x.lo)–\(x.hi)" }
                        return (SetRef(i: i, j: j), name(e.id), detail)
                    }
                    j += 1
                }
            }
            i += 1
            j = 0
        }
        return nil
    }

    // MARK: - afslutning og progression

    /// finish(): progressionen køres for hver person for sig, og hver får sin egen logpost.
    func finish() {
        guard let a = active, isLoaded else { return }
        var result: [FinishGroup] = []
        let ts = nowMs()
        let date = Logic.dateString(Date())
        for p in a.profiles {
            var adj: [Adjustment] = []
            var entries: [LogEntry] = []
            for e in a.ex {
                guard let x = EX(e.id), let person = e[p] else { continue }
                let sets = Logic.loggedSets(person.sets)
                entries.append(LogEntry(ex: e.id, sets: sets))
                if sets.isEmpty { continue }
                let s = st(p, e.id)
                var v = s.values
                let old = v.w
                let msg = Logic.progress(&v, x: x, sets: sets, step: inc(e.id), readiness: a.readiness(p))
                s.values = v
                adj.append(Adjustment(n: x.n, from: old, to: v.w ?? 0, msg: msg))
            }
            let trained = groupsOfIds(entries.filter { !$0.sets.isEmpty }.map(\.ex))
            let rec = LogRecord(
                profile: p,
                name: a.name,
                groups: trained.isEmpty ? a.groups : trained,
                date: date,
                ts: ts,
                readiness: a.readiness(p),
                entries: entries
            )
            context.insert(WorkoutLog(rec))
            logs[p, default: []].append(rec)
            index[p, default: ProfileIndex()].add(rec)
            result.append(FinishGroup(profile: p, name: name(of: p), items: adj))
        }
        save()
        active = nil
        nextRef = [:]
        saveActive()
        timers.stopAll()
        finishGroups = result
    }

    func doDeload(_ p: Profile) {
        for (k, s) in progress[p] ?? [:] {
            guard let x = EX(k) else { continue }
            var v = s.values
            Logic.deload(&v, x: x, inc: inc(k))
            s.values = v
        }
        settings.setDeload(p, logCount(p))
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
                a.ex[i] = makeSessionEx(nid, a)
            }
            active = a
            nextRef = [:]
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
        a.ex.append(makeSessionEx(id, a))
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
        context.insert(CustomExercise(def))
        customEx[id] = def
        var L = groupList(g)
        L.append(id)
        groups[g] = L
        let intoSession = toSession && active != nil
        if intoSession, var a = active {
            a.ex.append(makeSessionEx(id, a))
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

    // MARK: - backup

    /// Hele datasættet som værdier (til backup i baggrunden).
    func snapshot() -> BackupData {
        func data(_ p: Profile) -> ProfileData {
            var ex: [String: ProgressValues] = [:]
            for (id, s) in progress[p] ?? [:] { ex[id] = s.values }
            return ProfileData(name: name(of: p), ex: ex, log: logs[p] ?? [], deload: settings.deload(p))
        }
        return BackupData(
            sourceVersion: 4,
            groups: groups,
            incU: settings.incU,
            incL: settings.incL,
            customEx: customEx.values.sorted { $0.id < $1.id },
            favs: favs,
            louis: data(.louis),
            buddy: data(.buddy)
        )
    }

    /// JSON.stringify(D), lavet i baggrunden.
    func exportData() async -> Data {
        let snap = snapshot()
        return await Task.detached(priority: .userInitiated) { Backup.serialize(snap) }.value
    }

    private func weeklyBackupIfDue() {
        guard isLoaded, BackupFiles.weeklyDue else { return }
        let snap = snapshot()
        Task.detached(priority: .background) {
            BackupFiles.writeWeekly(Backup.serialize(snap))
        }
    }

    /// Kaldes, når appen kommer i forgrunden.
    func appDidBecomeActive() {
        timers.checkExpired()
        weeklyBackupIfDue()
    }

    /// Erstatter data med backuppen. En v4-backup erstatter alt. En v2/v3-backup er Louis' data;
    /// `keepBuddy` afgør, om makkerens data beholdes.
    func applyBackup(_ b: BackupData, keepBuddy: Bool) {
        var data = b
        if b.buddy == nil {
            let current = snapshot().buddy
            data.buddy = keepBuddy ? current : ProfileData(name: current?.name ?? "Makker", ex: [:], log: [], deload: 0)
        }
        replaceAll(with: data)
        toast("Backup gendannet.")
    }

    /// wipe(): alt slettes, også makkerens data.
    func wipe() {
        replaceAll(with: BackupData(
            sourceVersion: 4, groups: Catalog.defaultGroups, incU: 2.5, incL: 5, customEx: [], favs: [],
            louis: ProfileData(name: "Louis", ex: [:], log: [], deload: 0),
            buddy: ProfileData(name: settings.buddyName, ex: [:], log: [], deload: 0)
        ))
        active = nil
        picked = []
        nextRef = [:]
        saveActive()
        timers.stopAll()
        toast("Alt er slettet.")
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        do {
            try context.delete(model: type)
        } catch {
            for m in (try? context.fetch(FetchDescriptor<T>())) ?? [] { context.delete(m) }
        }
    }

    private func replaceAll(with b: BackupData) {
        deleteAll(WorkoutLog.self)
        deleteAll(ProfileProgress.self)
        deleteAll(CustomExercise.self)
        deleteAll(ExerciseProgress.self)
        save()

        customEx = [:]
        for c in b.customEx {
            customEx[c.id] = c
            context.insert(CustomExercise(c))
        }

        let buddy = b.buddy ?? ProfileData(name: settings.buddyName, ex: [:], log: [], deload: 0)
        progress = [.louis: [:], .buddy: [:]]
        for (p, d) in [(Profile.louis, b.louis), (Profile.buddy, buddy)] {
            for (id, v) in d.ex {
                let m = ProfileProgress(profile: p, ex: id, values: v)
                context.insert(m)
                progress[p, default: [:]][id] = m
            }
            let recs = d.log.map { r -> LogRecord in
                var r = r
                r.profile = p
                return r
            }
            for r in recs { context.insert(WorkoutLog(r)) }
            logs[p] = recs
            index[p] = ProfileIndex.build(recs)
            settings.setDeload(p, d.deload)
        }
        settings.buddyName = buddy.name.isEmpty ? "Makker" : buddy.name

        groups = b.groups
        favs = b.favs
        settings.setGroups(groups)
        settings.setFavs(favs)
        settings.incU = b.incU
        settings.incL = b.incL
        settings.v = 4

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

    /// applyQuickParam(): gælder Louis.
    func applyQuick(_ url: URL) {
        guard let w = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "w" })?.value,
            let n = num(w) else { return }
        if var a = active {
            var applied = false
            for i in a.ex.indices {
                guard var person = a.ex[i][.louis] else { continue }
                for j in person.sets.indices where !applied && !person.sets[j].done {
                    person.sets[j].w = fmt(n)
                    applied = true
                }
                a.ex[i][.louis] = person
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
