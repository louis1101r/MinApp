import Foundation

/// En øvelse som i webappens BUILTIN_EX / customEx.
/// n = navn, m = detaljeret muskel, t = "u"|"l" (vælger vægtspring), lo/hi = rep-interval,
/// s = standard antal sæt, r = pause i sekunder, d = egen beskrivelse (kun egne øvelser).
struct ExerciseDef: Codable, Hashable {
    var id: String
    var n: String
    var m: String
    var t: String
    var lo: Int
    var hi: Int
    var s: Int
    var r: Int
    var d: String? = nil
}

/// EXDESC: s = udgangsstilling, u = udførelse, f = fokuspunkter, x = typiske fejl.
struct ExerciseDesc {
    var s: String
    var u: String
    var f: [String]
    var x: [String]
}

enum Catalog {
    static let builtin: [String: ExerciseDef] = Dictionary(
        uniqueKeysWithValues: builtinList.map { ($0.id, $0) }
    )

    /// TG: træningsgrupper. Rækkefølgen betyder noget.
    static let tg = ["Bryst", "Ryg", "Skulder", "Biceps", "Triceps", "Ben", "Mave"]
    static let big = ["Bryst", "Ryg", "Ben"]
    static let sessionOrder = ["Ben", "Bryst", "Ryg", "Skulder", "Triceps", "Biceps", "Mave"]
    static let tgMap: [String: String] = [
        "Ryg": "Ryg", "Bagskulder": "Skulder", "Biceps": "Biceps", "Bryst": "Bryst", "Skulder": "Skulder",
        "Triceps": "Triceps", "Forlår": "Ben", "Baglår": "Ben", "Balder": "Ben", "Lægge": "Ben",
        "Ben": "Ben", "Mave": "Mave",
    ]
    static let pairs: [[String]] = [["Bryst", "Triceps"], ["Ryg", "Biceps"], ["Ben"], ["Skulder", "Mave"]]
    static let defaultGroups: [String: [String]] = [
        "Bryst": ["bench", "incdb", "cflye", "dip"],
        "Ryg": ["pullup", "row", "cablerow", "pullover"],
        "Skulder": ["ohp", "lat", "facepull"],
        "Biceps": ["curl", "inccurl", "hammer"],
        "Triceps": ["pushdown", "ohtri", "skull"],
        "Ben": ["squat", "rdl", "legpress", "legcurl", "legext", "calf"],
        "Mave": ["abs", "legraise"],
    ]

    static let readinessLabels: [(Int, String)] = [(1, "Slidt"), (2, "Træt"), (3, "Normal"), (4, "Frisk"), (5, "Top")]

    static func readyMult(_ r: Int) -> Double {
        switch r {
        case 1: return 0.9
        case 2: return 0.95
        case 5: return 1.025
        default: return 1
        }
    }
}

// MARK: - Hjælpefunktioner der svarer til webappens

/// JS Math.round(v/s)*s. Math.round runder .5 op mod +∞, derfor floor(x + 0.5).
func rnd(_ v: Double, _ s: Double) -> Double {
    (v / s + 0.5).rounded(.down) * s
}

/// fmt(): én decimal, komma som decimaltegn, "–" for manglende værdi.
func fmt(_ v: Double?) -> String {
    guard let v, v.isFinite else { return "–" }
    let r = (v * 10 + 0.5).rounded(.down) / 10
    if r == r.rounded(.towardZero), abs(r) < 1e15 {
        return String(Int(r))
    }
    return String(r).replacingOccurrences(of: ".", with: ",")
}

/// Number(v) for et inputfelt. Tom streng eller ugyldigt tal giver nil.
func num(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    if t.isEmpty { return nil }
    return Double(t)
}

/// Epley med "i tanken" lagt til.
func e1rm(_ w: Double, _ r: Double, _ rir: Double) -> Double {
    w * (1 + (r + rir) / 30)
}

func restLabel(_ r: Int) -> String {
    r >= 60 ? fmt(Double(r) / 60) + " min" : "\(r) sek"
}
