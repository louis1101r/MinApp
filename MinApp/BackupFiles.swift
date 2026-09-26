import Foundation

/// Backupfiler i appens Dokumenter-mappe, som ses i Filer under "På min iPhone → MinApp".
enum BackupFiles {
    static let preMigrationName = "backup-v3-før-makker.json"
    static let preMigrationRawFolder = "backup-v3-før-makker-database"
    private static let weeklyPrefix = "ugentlig-"
    private static let weeklyKeep = 8
    private static let lastWeeklyKey = "lastWeeklyBackup"
    private static let rawDoneKey = "v4RawBackupDone"

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Kopierer SwiftData-databasefilerne, før databasen åbnes første gang med v4-skemaet
    /// (SwiftData ændrer databasen i det øjeblik, den åbnes). Kører kun én gang.
    static func copyDatabaseBeforeV4() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: rawDoneKey) else { return }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = support.appendingPathComponent("default.store")
        if fm.fileExists(atPath: store.path) {
            let dest = documents.appendingPathComponent(preMigrationRawFolder)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let src = support.appendingPathComponent("default.store" + suffix)
                let dst = dest.appendingPathComponent("default.store" + suffix)
                if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
        defaults.set(true, forKey: rawDoneKey)
    }

    /// Skriver en JSON-backup (bruges af førmigrerings-backuppen). Overskriver aldrig.
    static func writeOnce(_ data: Data, name: String) {
        let url = documents.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static var weeklyDue: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastWeeklyKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= 7 * 86_400
    }

    /// Ugentlig backup: ugentlig-ÅÅÅÅ-MM-DD.json, højst 8 filer (de ældste slettes).
    static func writeWeekly(_ data: Data) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let url = documents.appendingPathComponent(weeklyPrefix + f.string(from: Date()) + ".json")
        do {
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: lastWeeklyKey)
        } catch {
            return
        }
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: documents.path)) ?? [])
            .filter { $0.hasPrefix(weeklyPrefix) && $0.hasSuffix(".json") }
            .sorted()
        for name in files.dropLast(weeklyKeep) {
            try? fm.removeItem(at: documents.appendingPathComponent(name))
        }
    }
}
