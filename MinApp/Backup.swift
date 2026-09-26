import Foundation

// Backupformatet.
//
// v4 = webappens v3 med Louis' data på de sædvanlige pladser (ex, log, deload) plus et ekstra
// felt "buddy": { name, ex, log, deload } med makkerens data. Webappen kan derfor stadig
// indlæse en v4-backup (den læser Louis og ignorerer makkeren), og v2/v3-backups læses
// uændret som Louis' data med præcis webappens migrate().

enum BackupError: Error {
    case unreadable
}

enum Backup {
    // MARK: - læsning (doImport + migrate)

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
        var exMap = Catalog.builtin
        for c in customEx { exMap[c.id] = c }
        let EX: ExLookup = { exMap[$0] }

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
                    guard let id = str(raw), EX(id) != nil else { continue }
                    let tg = Logic.tgOf(id, EX)
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
            groups[t] = (groups[t] ?? []).filter { EX($0) != nil }
        }

        // d.inc=d.inc||{u:2.5,l:5}
        var incU = 2.5
        var incL = 5.0
        if let inc = d["inc"] as? [String: Any] {
            incU = dbl(inc["u"]) ?? 2.5
            incL = dbl(inc["l"]) ?? 5
        }

        let favs: [[String]] = ((d["favs"] as? [Any]) ?? []).compactMap { f in
            (f as? [Any]).map { $0.compactMap { str($0) } }
        }

        let louis = profileData(d, profile: .louis, name: "Louis", EX: EX)
        var buddy: ProfileData?
        if let b = d["buddy"] as? [String: Any] {
            buddy = profileData(b, profile: .buddy, name: str(b["name"]) ?? "Makker", EX: EX)
        }
        let v = int(d["v"]) ?? 0
        let version = buddy != nil || v >= 4 ? 4 : (d["groups"] == nil ? 2 : 3)

        return BackupData(
            sourceVersion: version,
            groups: groups,
            incU: incU,
            incL: incL,
            customEx: customEx,
            favs: favs,
            louis: louis,
            buddy: buddy
        )
    }

    /// ex, log og deload for én profil.
    private static func profileData(_ d: [String: Any], profile: Profile, name: String, EX: ExLookup) -> ProfileData {
        var ex: [String: ProgressValues] = [:]
        if let e = d["ex"] as? [String: Any] {
            for (id, raw) in e {
                guard let p = raw as? [String: Any] else { continue }
                ex[id] = ProgressValues(
                    w: dbl(p["w"]),
                    sets: int(p["sets"]) ?? EX(id)?.s ?? 3,
                    stall: int(p["stall"]) ?? 0,
                    wins: int(p["wins"]) ?? 0
                )
            }
        }

        var log: [LogRecord] = []
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
            let savedGroups = (l["groups"] as? [Any]).map { $0.compactMap { str($0) } }
            log.append(LogRecord(
                profile: profile,
                name: str(l["name"]) ?? "",
                groups: Logic.logGroups(savedGroups, entries, EX),
                date: str(l["date"]) ?? "",
                ts: dbl(l["ts"]) ?? 0,
                readiness: int(l["readiness"]) ?? 3,
                entries: entries
            ))
        }
        // Loggen holdes i tidsrækkefølge.
        if !zip(log, log.dropFirst()).allSatisfy({ $0.ts <= $1.ts }) {
            log = log.enumerated()
                .sorted { $0.element.ts != $1.element.ts ? $0.element.ts < $1.element.ts : $0.offset < $1.offset }
                .map(\.element)
        }

        return ProfileData(name: name, ex: ex, log: log, deload: int(d["deload"]) ?? 0)
    }

    // MARK: - skrivning (JSON.stringify(D))

    /// version 3 skriver kun Louis (som webappen); version 4 tager makkeren med.
    static func serialize(_ b: BackupData, version: Int = 4) -> Data {
        var d = profileJSON(b.louis)
        d["v"] = version

        var groups: [String: Any] = [:]
        for (k, v) in b.groups { groups[k] = v }
        d["groups"] = groups
        d["inc"] = ["u": b.incU, "l": b.incL]

        var custom: [String: Any] = [:]
        for c in b.customEx {
            var item: [String: Any] = [:]
            item["n"] = c.n
            item["m"] = c.m
            item["t"] = c.t
            item["lo"] = c.lo
            item["hi"] = c.hi
            item["s"] = c.s
            item["r"] = c.r
            item["d"] = c.d ?? ""
            custom[c.id] = item
        }
        d["customEx"] = custom
        d["favs"] = b.favs

        if version >= 4, let buddy = b.buddy {
            var bd = profileJSON(buddy)
            bd["name"] = buddy.name
            d["buddy"] = bd
        }
        return (try? JSONSerialization.data(withJSONObject: d, options: [.withoutEscapingSlashes])) ?? Data()
    }

    private static func profileJSON(_ p: ProfileData) -> [String: Any] {
        var ex: [String: Any] = [:]
        for (id, s) in p.ex {
            var item: [String: Any] = ["sets": s.sets, "stall": s.stall, "wins": s.wins]
            if let w = s.w {
                item["w"] = w
            } else {
                item["w"] = NSNull()
            }
            ex[id] = item
        }

        var logArr: [Any] = []
        logArr.reserveCapacity(p.log.count)
        for l in p.log {
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

        var d: [String: Any] = [:]
        d["ex"] = ex
        d["log"] = logArr
        d["deload"] = p.deload
        return d
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
