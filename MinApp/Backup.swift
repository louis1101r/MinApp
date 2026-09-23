import Foundation

/// En backup i webappens format (D), læst og migreret som i migrate().
struct BackupData {
    var groups: [String: [String]]
    var incU: Double
    var incL: Double
    var ex: [String: ProgressValues]
    var log: [ParsedLog]
    var deload: Int
    var customEx: [ExerciseDef]
    var favs: [[String]]

    struct ProgressValues {
        var w: Double?
        var sets: Int?
        var stall: Int
        var wins: Int
    }

    struct ParsedLog {
        var name: String
        /// nil = gammel logpost uden groups; udledes af øvelserne (logGroups()).
        var groups: [String]?
        var date: String
        var ts: Double
        var readiness: Int
        var entries: [LogEntry]
    }

    /// Antal egne øvelser + øvelser med progression, til bekræftelsen.
    var exerciseCount: Int { ex.count }
}

enum BackupError: Error {
    case unreadable
}

enum Backup {
    /// doImport(): JSON.parse + tjek af formen + migrate().
    static func parse(_ data: Data) throws -> BackupData {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let d = obj as? [String: Any] else {
            throw BackupError.unreadable
        }
        // if(!parsed||!parsed.ex||!(parsed.prog||parsed.groups)) throw
        guard truthy(d["ex"]), truthy(d["prog"]) || truthy(d["groups"]) else {
            throw BackupError.unreadable
        }

        // d.customEx=d.customEx||{}
        var customEx: [ExerciseDef] = []
        if let c = d["customEx"] as? [String: Any] {
            for (id, raw) in c {
                guard let e = raw as? [String: Any] else { continue }
                customEx.append(ExerciseDef(
                    id: id,
                    n: str(e["n"]) ?? id,
                    m: str(e["m"]) ?? "",
                    t: str(e["t"]) ?? "u",
                    lo: int(e["lo"]) ?? 8,
                    hi: int(e["hi"]) ?? 12,
                    s: int(e["s"]) ?? 3,
                    r: int(e["r"]) ?? 90,
                    d: str(e["d"]) ?? ""
                ))
            }
        }
        // Egne øvelser har id "custom_<base36-tid>", så sortering giver oprettelsesrækkefølgen.
        customEx.sort { $0.id < $1.id }

        // EX=Object.assign({},BUILTIN_EX,d.customEx)
        var EX = Catalog.builtin
        for c in customEx { EX[c.id] = c }
        func tgOf(_ id: String) -> String {
            let m = EX[id]?.m ?? ""
            return Catalog.tgMap[m] ?? m
        }

        // d.groups: bygges ud fra v2's prog, hvis de mangler.
        var groups: [String: [String]]
        if let g = d["groups"] as? [String: Any] {
            groups = [:]
            for (k, v) in g {
                groups[k] = (v as? [Any] ?? []).compactMap { str($0) }
            }
        } else {
            var g: [String: [String]] = [:]
            for t in Catalog.tg { g[t] = [] }
            for t in (d["prog"] as? [Any]) ?? [] {
                guard let tpl = t as? [String: Any] else { continue }
                for raw in (tpl["e"] as? [Any]) ?? [] {
                    guard let id = str(raw), EX[id] != nil else { continue }
                    let tg = tgOf(id)
                    if var list = g[tg], !list.contains(id) {
                        list.append(id)
                        g[tg] = list
                    }
                }
            }
            for t in Catalog.tg where (g[t] ?? []).isEmpty {
                g[t] = Catalog.defaultGroups[t] ?? []
            }
            groups = g
        }
        // TG.forEach: fjern ukendte id'er
        for t in Catalog.tg {
            groups[t] = (groups[t] ?? []).filter { EX[$0] != nil }
        }

        // d.inc=d.inc||{u:2.5,l:5}
        var incU = 2.5
        var incL = 5.0
        if let inc = d["inc"] as? [String: Any] {
            incU = dbl(inc["u"]) ?? 2.5
            incL = dbl(inc["l"]) ?? 5
        }

        var ex: [String: BackupData.ProgressValues] = [:]
        if let e = d["ex"] as? [String: Any] {
            for (id, raw) in e {
                guard let p = raw as? [String: Any] else { continue }
                ex[id] = BackupData.ProgressValues(
                    w: dbl(p["w"]),
                    sets: int(p["sets"]),
                    stall: int(p["stall"]) ?? 0,
                    wins: int(p["wins"]) ?? 0
                )
            }
        }

        var log: [BackupData.ParsedLog] = []
        for raw in (d["log"] as? [Any]) ?? [] {
            guard let l = raw as? [String: Any] else { continue }
            var entries: [LogEntry] = []
            for er in (l["entries"] as? [Any]) ?? [] {
                guard let e = er as? [String: Any], let id = str(e["ex"]) else { continue }
                let sets: [LogSet] = ((e["sets"] as? [Any]) ?? []).compactMap { sr in
                    guard let s = sr as? [String: Any] else { return nil }
                    return LogSet(w: dbl(s["w"]) ?? 0, r: dbl(s["r"]) ?? 0, rir: dbl(s["rir"]) ?? 0)
                }
                entries.append(LogEntry(ex: id, sets: sets))
            }
            let groups = (l["groups"] as? [Any]).map { $0.compactMap { str($0) } }
            log.append(BackupData.ParsedLog(
                name: str(l["name"]) ?? "",
                groups: groups,
                date: str(l["date"]) ?? "",
                ts: dbl(l["ts"]) ?? 0,
                readiness: int(l["readiness"]) ?? 3,
                entries: entries
            ))
        }

        let favs: [[String]] = ((d["favs"] as? [Any]) ?? []).compactMap { f in
            (f as? [Any]).map { $0.compactMap { str($0) } }
        }

        return BackupData(
            groups: groups,
            incU: incU,
            incL: incL,
            ex: ex,
            log: log,
            deload: int(d["deload"]) ?? 0,
            customEx: customEx,
            favs: favs
        )
    }

    // MARK: - JSON-hjælpere med JavaScripts sandhedsværdier

    private static func truthy(_ a: Any?) -> Bool {
        guard let a, !(a is NSNull) else { return false }
        if let n = a as? NSNumber { return n.doubleValue != 0 && !n.doubleValue.isNaN }
        if let s = a as? String { return !s.isEmpty }
        return true
    }

    private static func str(_ a: Any?) -> String? {
        if let s = a as? String { return s }
        if let n = a as? NSNumber { return n.stringValue }
        return nil
    }

    private static func dbl(_ a: Any?) -> Double? {
        if let n = a as? NSNumber { return n.doubleValue }
        if let s = a as? String { return num(s) }
        return nil
    }

    private static func int(_ a: Any?) -> Int? {
        guard let v = dbl(a), v.isFinite else { return nil }
        return Int(jsRound(v))
    }
}
