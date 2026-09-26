import ActivityKit
import AudioToolbox
import Foundation
import Observation
import UIKit
import UserNotifications

/// En persons igangværende pause.
struct RunningRest: Equatable {
    var start: Date
    var end: Date
}

/// Hviletimere: rest(sec), adjustRest(±15), stopTimer() fra webappen, én per person.
/// Viser nedtællingerne i appen, i én fælles Live Activity (Dynamic Island og låseskærm)
/// og planlægger en lokal notifikation per person, når pausen er slut.
@MainActor
@Observable
final class RestTimers {
    private(set) var running: [Profile: RunningRest] = [:]
    private var workout = ""
    /// Personerne i træningen i visningsrækkefølge, med navn.
    private var people: [(Profile, String)] = []
    private var title: [Profile: String] = [:]
    private var detail: [Profile: String] = [:]
    private var last: [Profile: String] = [:]
    private var watcher: Task<Void, Never>?
    private var activity: Activity<RestAttributes>?

    var anyRunning: Bool { !running.isEmpty }

    func isRunning(_ p: Profile) -> Bool {
        running[p] != nil
    }

    /// Personer med pause, i træningens rækkefølge.
    var runningProfiles: [Profile] {
        let order = people.map(\.0)
        return running.keys.sorted { (order.firstIndex(of: $0) ?? 9) < (order.firstIndex(of: $1) ?? 9) }
    }

    func displayName(_ p: Profile) -> String {
        people.first { $0.0 == p }?.1 ?? (p == .louis ? "Louis" : "Makker")
    }

    var together: Bool { people.count > 1 }

    init() {
        restoreFromActivity()
    }

    /// Hvis appen er startet igen (fx af en knap i Live Activity), overtages de kørende pauser.
    private func restoreFromActivity() {
        guard let a = Activity<RestAttributes>.activities.first else { return }
        activity = a
        workout = a.attributes.workout
        let now = Date()
        for person in a.content.state.people {
            guard let p = Profile(rawValue: person.profile) else { continue }
            people.append((p, person.name))
            title[p] = person.title
            detail[p] = person.detail
            last[p] = person.last
            if let s = person.startDate, let e = person.endDate, e > now {
                running[p] = RunningRest(start: s, end: e)
            }
        }
        if anyRunning { watch() }
    }

    func start(_ p: Profile, seconds: Int, workout: String, people: [(Profile, String)],
               title: String, detail: String, last: String?) {
        self.workout = workout
        self.people = people
        self.title[p] = title
        self.detail[p] = detail
        if let last { self.last[p] = last }
        let now = Date()
        running[p] = RunningRest(start: now, end: now.addingTimeInterval(TimeInterval(seconds)))
        showActivity()
        scheduleNotification(p)
        watch()
    }

    /// adjustRest(±15): flytter personens sluttidspunkt. Gør intet, hvis personen ikke holder pause.
    func adjust(_ p: Profile, _ seconds: Int) {
        guard var r = running[p] else { return }
        r.end = r.end.addingTimeInterval(TimeInterval(seconds))
        if r.end <= Date() {
            // Den planlagte notifikation gælder det gamle tidspunkt, så den fjernes.
            stop(p)
            Self.vibrate()
            return
        }
        running[p] = r
        showActivity()
        scheduleNotification(p)
    }

    /// stopTimer() for én person.
    func stop(_ p: Profile) {
        stop(p, removeNotification: true)
    }

    /// Alle pauser stoppes, og Live Activity fjernes (afslut/afbryd træning).
    func stopAll() {
        for p in Array(running.keys) {
            removeNotification(p)
        }
        running = [:]
        watcher?.cancel()
        watcher = nil
        endActivities()
    }

    private func stop(_ p: Profile, removeNotification remove: Bool) {
        running[p] = nil
        if remove { removeNotification(p) }
        if running.isEmpty {
            watcher?.cancel()
            watcher = nil
            endActivities()
        } else {
            showActivity()
        }
    }

    /// Kaldes når appen kommer i forgrunden igen: stop pauser, der er udløbet i mellemtiden.
    func checkExpired() {
        let now = Date()
        var any = false
        for (p, r) in running where r.end <= now {
            stop(p, removeNotification: false)
            any = true
        }
        if any { Self.vibrate() }
        if running.isEmpty { endActivities() }
    }

    /// Pausen er slut: appen vibrerer, notifikationen får lov at komme.
    private func complete(_ p: Profile) {
        stop(p, removeNotification: false)
        Self.vibrate()
    }

    /// navigator.vibrate(...) i webappen: en rigtig vibration, ingen lyd.
    static func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func watch() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                let now = Date()
                for (p, r) in self.running where r.end <= now {
                    self.complete(p)
                }
                if self.running.isEmpty {
                    self.watcher = nil
                    return
                }
            }
        }
    }

    // MARK: - Live Activity

    private var state: RestAttributes.ContentState {
        RestAttributes.ContentState(people: people.map { p, name in
            RestAttributes.Person(
                profile: p.rawValue,
                name: name,
                startDate: running[p]?.start,
                endDate: running[p]?.end,
                title: title[p] ?? "",
                detail: detail[p] ?? "",
                last: last[p] ?? ""
            )
        })
    }

    /// Viser pauserne i Live Activity. En eksisterende aktivitet opdateres i stedet for at
    /// starte en ny, så det også virker, når appen er i baggrunden (knapperne i Live Activity).
    private func showActivity() {
        let stale = running.values.map(\.end).max()
        let content = ActivityContent(state: state, staleDate: stale)
        let all = Activity<RestAttributes>.activities
        if let existing = activity ?? all.first {
            activity = existing
            for other in all where other.id != existing.id {
                Task { await other.end(nil, dismissalPolicy: .immediate) }
            }
            Task { await existing.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity<RestAttributes>.request(
            attributes: RestAttributes(workout: workout),
            content: content,
            pushType: nil
        )
    }

    private func endActivities() {
        activity = nil
        for a in Activity<RestAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Notifikation

    private static func notificationId(_ p: Profile) -> String {
        "rest-end-" + p.rawValue
    }

    private func removeNotification(_ p: Profile) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId(p)])
    }

    private func scheduleNotification(_ p: Profile) {
        guard let r = running[p] else { return }
        let center = UNUserNotificationCenter.current()
        removeNotification(p)
        let content = UNMutableNotificationContent()
        content.title = together ? "Pausen er slut · " + displayName(p) : "Pausen er slut"
        let t = title[p] ?? ""
        let d = detail[p] ?? ""
        content.body = t + (d.isEmpty ? "" : " · " + d)
        // Lyd er nødvendig for at telefonen vibrerer, når appen ikke er åben.
        // På lydløs vibrerer den kun.
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, r.end.timeIntervalSinceNow), repeats: false)
        center.add(
            UNNotificationRequest(identifier: Self.notificationId(p), content: content, trigger: trigger),
            withCompletionHandler: nil
        )
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// Når appen er åben, vises notifikationen som banner uden lyd; appen vibrerer selv.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
