import Foundation

// Lokale tests af den rene logik (ingen iOS SDK nødvendig).
// Kør: tools/logic-tests/run.sh

var failures = 0
func check(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if !cond {
        failures += 1
        print("FEJL (linje \(line)): \(msg)")
    }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String, line: Int = #line) {
    check(a == b, "\(msg): fik \(a), forventede \(b)", line: line)
}
func time<T>(_ label: String, _ f: () throws -> T) rethrows -> T {
    let t = Date()
    let r = try f()
    print(String(format: "  %-44@ %7.1f ms", label as NSString, Date().timeIntervalSince(t) * 1000))
    return r
}

let EX: ExLookup = { Catalog.builtin[$0] }

// MARK: hjælpefunktioner
eq(fmt(72.5), "72,5", "fmt")
eq(fmt(80), "80", "fmt heltal")
eq(fmt(nil), "–", "fmt nil")
eq(rnd(81.3, 1.25), 81.25, "rnd")
eq(jsRound(-2.5), -2, "Math.round(-2.5)")
eq(Catalog.builtinList.count, 51, "antal indbyggede øvelser")
eq(Catalog.desc.count, 51, "antal beskrivelser")

// MARK: progression (finish)
let bench = Catalog.builtin["bench"]!   // lo 5, hi 8, s 4
func sets(_ reps: [Double], w: Double = 100, lastRir: Double = 2) -> [LogSet] {
    reps.enumerated().map { i, r in LogSet(w: w, r: r, rir: i == reps.count - 1 ? lastRir : 2) }
}
do {
    var s = ProgressValues(w: 100, sets: 4, stall: 0, wins: 0)
    let m = Logic.progress(&s, x: bench, sets: sets([8, 8, 8, 8], lastRir: 3), step: 2.5, readiness: 3)
    eq(s.w, 105, "klart over målet: +2 spring"); eq(s.wins, 1, "wins"); eq(m, "klart over målet", "msg")
}
do {
    var s = ProgressValues(w: 100, sets: 4, stall: 1, wins: 0)
    let m = Logic.progress(&s, x: bench, sets: sets([8, 9, 8, 8]), step: 2.5, readiness: 3)
    eq(s.w, 102.5, "alle sæt i toppen: +1 spring"); eq(s.stall, 0, "stall nulstilles"); eq(m, "alle sæt i toppen", "msg")
}
do {
    var s = ProgressValues(w: 100, sets: 4, stall: 1, wins: 2)
    let m = Logic.progress(&s, x: bench, sets: sets([8, 7, 6, 6]), step: 2.5, readiness: 3)
    eq(s.w, 100, "inden for intervallet"); eq(s.stall, 0, "stall"); eq(s.wins, 2, "wins uændret"); eq(m, "hold vægten, jagt gentagelser", "msg")
}
do {
    var s = ProgressValues(w: 100, sets: 4, stall: 0, wins: 2)
    var m = Logic.progress(&s, x: bench, sets: sets([6, 5, 4]), step: 2.5, readiness: 3)
    eq(s.w, 100, "under målet første gang"); eq(s.stall, 1, "stall 1"); eq(m, "under målet, samme vægt igen", "msg")
    m = Logic.progress(&s, x: bench, sets: sets([5, 4, 4]), step: 2.5, readiness: 3)
    eq(s.w, 90, "under målet to gange: -10 %"); eq(s.stall, 0, "stall"); eq(s.wins, 0, "wins"); eq(s.sets, 4, "sets = standard")
    eq(m, "under målet to gange, ned 10 %", "msg")
}
do {
    var s = ProgressValues(w: 100, sets: 4, stall: 0, wins: 2)
    let m = Logic.progress(&s, x: bench, sets: sets([8, 8, 8, 8]), step: 2.5, readiness: 4)
    eq(s.sets, 5, "tredje stigning på frisk dag: +1 sæt"); eq(s.wins, 0, "wins nulstilles"); eq(m, "alle sæt i toppen, plus ét sæt", "msg")
    var s2 = ProgressValues(w: 100, sets: 6, stall: 0, wins: 2)
    _ = Logic.progress(&s2, x: bench, sets: sets([8, 8]), step: 2.5, readiness: 5)
    eq(s2.sets, 6, "loft: standard + 2")
}
do {
    let logged = Logic.loggedSets([
        ActiveSet(w: "80", r: "8", rir: "", done: true),
        ActiveSet(w: "", r: "8", rir: "1", done: true),
        ActiveSet(w: "80", r: "0", rir: "1", done: true),
        ActiveSet(w: "82,5", r: "6", rir: "3", done: false),
    ])
    eq(logged, [LogSet(w: 80, r: 8, rir: 2), LogSet(w: 82.5, r: 6, rir: 3)], "loggedSets")
}
do {
    let p1 = Logic.sessionPerson(ProgressValues(w: 100, sets: 4, stall: 0, wins: 0), readiness: 1, inc: 2.5)
    eq(p1.sets.count, 3, "slidt: et sæt færre"); eq(p1.target, 90, "slidt: -10 %")
    let p5 = Logic.sessionPerson(ProgressValues(w: 100, sets: 2, stall: 0, wins: 0), readiness: 5, inc: 2.5)
    eq(p5.sets.count, 2, "mindst 2 sæt"); eq(p5.target, 102.5, "top: +2,5 %")
    let p0 = Logic.sessionPerson(ProgressValues(w: nil, sets: 3, stall: 0, wins: 0), readiness: 3, inc: 5)
    eq(p0.target, nil, "ingen vægt endnu")
}
do {
    var s = ProgressValues(w: 101, sets: 5, stall: 1, wins: 2)
    Logic.deload(&s, x: bench, inc: 2.5)
    eq(s.w, 91.25, "deload"); eq(s.sets, 4, "deload sæt"); eq(s.stall, 0, "deload stall")
}

// MARK: v2-migrering
do {
    let v2 = """
    {"prog":[{"n":"A","e":["bench","curl","findesikke"]},{"n":"B","e":["squat","bench"]}],"q":1,
     "ex":{"bench":{"w":80,"sets":4,"stall":0,"wins":1}},
     "log":[{"name":"A","date":"01.01.2024","ts":1704100000000,"readiness":3,
             "entries":[{"ex":"bench","sets":[{"w":80,"r":8,"rir":2}]},{"ex":"curl","sets":[]}]}]}
    """
    let b = try Backup.parse(Data(v2.utf8))
    eq(b.sourceVersion, 2, "v2 genkendt")
    eq(b.groups["Bryst"]!, ["bench"], "v2: Bryst fra prog")
    eq(b.groups["Biceps"]!, ["curl"], "v2: Biceps fra prog")
    eq(b.groups["Ben"]!, ["squat"], "v2: Ben fra prog")
    eq(b.groups["Ryg"]!, Catalog.defaultGroups["Ryg"]!, "v2: tom gruppe får standard")
    eq(b.louis.log[0].groups, ["Bryst"], "logGroups: kun øvelser med sæt")
    eq(b.louis.ex["bench"]!.w, 80, "v2: vægt")
    check(b.buddy == nil, "v2 har ingen makker")
}
do {
    let bad = try? Backup.parse(Data("{\"log\":[]}".utf8))
    check(bad == nil, "backup uden ex afvises")
}

// MARK: syntetiske data
func synthetic(logs n: Int, profile: Profile) -> [LogRecord] {
    let ids = Catalog.builtinList.map(\.id)
    let start = 1_600_000_000_000.0
    return (0..<n).map { i in
        let entries = (0..<6).map { k -> LogEntry in
            let id = ids[(i * 7 + k * 5) % ids.count]
            let sets = (0..<4).map { j in LogSet(w: 40 + Double((i + j) % 60), r: Double(5 + (i + k + j) % 8), rir: Double(j % 4)) }
            return LogEntry(ex: id, sets: sets)
        }
        let ts = start + Double(i) * 86_400_000
        return LogRecord(profile: profile, name: "Træning \(i)",
                         groups: Logic.groupsOfIds(entries.map(\.ex), EX),
                         date: Logic.dateString(Date(timeIntervalSince1970: ts / 1000)),
                         ts: ts, readiness: 1 + i % 5, entries: entries)
    }
}
func progressFor(_ ids: [String]) -> [String: ProgressValues] {
    var m: [String: ProgressValues] = [:]
    for (i, id) in ids.enumerated() { m[id] = ProgressValues(w: i % 3 == 0 ? nil : Double(20 + i), sets: 3, stall: i % 2, wins: i % 3) }
    return m
}

print("Ydelse (3.000 træninger for Louis + 500 for makker):")
let louisLog = synthetic(logs: 3000, profile: .louis)
let buddyLog = synthetic(logs: 500, profile: .buddy)
let full = BackupData(
    sourceVersion: 4,
    groups: Catalog.defaultGroups, incU: 2.5, incL: 5,
    customEx: [ExerciseDef(id: "custom_abc", n: "Egen øvelse", m: "Bryst", t: "u", lo: 8, hi: 12, s: 3, r: 90, d: "Tekst")],
    favs: [["Bryst", "Biceps"]],
    louis: ProfileData(name: "Louis", ex: progressFor(Catalog.builtinList.map(\.id)), log: louisLog, deload: 12),
    buddy: ProfileData(name: "Anna", ex: progressFor(["bench", "squat"]), log: buddyLog, deload: 0)
)
let json = time("skriv backup (JSON)") { Backup.serialize(full) }
print(String(format: "  %-44@ %7.1f MB", "backupstørrelse" as NSString, Double(json.count) / 1_000_000))
let parsed = try time("læs backup + migrate()") { try Backup.parse(json) }
let ix = time("byg cache for Louis (3.000)") { ProfileIndex.build(parsed.louis.log) }
_ = time("byg cache for makker (500)") { ProfileIndex.build(parsed.buddy!.log) }
var ix2 = ix
time("tilføj én træning til cachen") { ix2.add(louisLog[0]) }
_ = time("opslag: statistik for alle øvelser") { Catalog.builtinList.map { ix.exStats($0.id).count }.reduce(0, +) }

// MARK: v4 rundtur
eq(parsed.sourceVersion, 4, "v4 genkendt")
eq(parsed.louis.log.count, 3000, "Louis' log bevaret")
eq(parsed.buddy?.log.count, 500, "makkerens log bevaret")
eq(parsed.buddy?.name, "Anna", "makkerens navn")
eq(parsed.louis.deload, 12, "deload bevaret")
eq(parsed.louis.ex["pulldown"], full.louis.ex["pulldown"], "progression bevaret")
eq(parsed.louis.ex["pullup"]?.w, nil, "w = null bevaret")
eq(parsed.louis.log[1234], full.louis.log[1234], "logpost bevaret")
eq(parsed.buddy!.log[10].profile, .buddy, "makkerens poster har makker-profil")
eq(parsed.customEx.first?.n, "Egen øvelse", "egen øvelse bevaret")
eq(parsed.favs, [["Bryst", "Biceps"]], "favoritter bevaret")
eq(ix.count, 3000, "cache: antal")
let direct = louisLog.flatMap { l in l.entries.filter { $0.ex == "bench" && !$0.sets.isEmpty } }.count
eq(ix.exStats("bench").count, direct, "cache: exStats svarer til gennemløb")

// MARK: v3-skrivning (til webappen og førmigrerings-backuppen)
let v3 = Backup.serialize(full, version: 3)
let v3obj = try JSONSerialization.jsonObject(with: v3) as! [String: Any]
check(v3obj["buddy"] == nil, "v3 uden makker")
eq(v3obj["v"] as? Int, 3, "v3 har v=3")
let v3parsed = try Backup.parse(v3)
eq(v3parsed.sourceVersion, 3, "v3 genkendt")
check(v3parsed.buddy == nil, "v3 går kun til Louis")

// Til webapp-testen
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try Backup.serialize(BackupData(sourceVersion: 4, groups: full.groups, incU: 2.5, incL: 5, customEx: full.customEx,
                                favs: full.favs,
                                louis: ProfileData(name: "Louis", ex: full.louis.ex, log: Array(louisLog.prefix(5)), deload: 0),
                                buddy: ProfileData(name: "Anna", ex: full.buddy!.ex, log: Array(buddyLog.prefix(2)), deload: 0)))
    .write(to: outDir.appendingPathComponent("v4-sample.json"))

print(failures == 0 ? "Alle tests bestået." : "\(failures) test(s) fejlede.")
exit(failures == 0 ? 0 : 1)
