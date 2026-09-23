import ActivityKit
import AudioToolbox
import Foundation
import Observation
import UIKit
import UserNotifications

/// Hviletimer: rest(sec), adjustRest(±15), stopTimer() fra webappen.
/// Viser nedtællingen i appen, som Live Activity (Dynamic Island og låseskærm)
/// og planlægger en lokal notifikation, når pausen er slut.
@MainActor
@Observable
final class RestTimer {
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private var workout = ""
    private var title = ""
    private var detail = ""
    private var watcher: Task<Void, Never>?
    private var activity: Activity<RestActivityAttributes>?

    private static let notificationId = "rest-end"

    var isRunning: Bool { endDate != nil }

    func start(seconds: Int, workout: String, title: String, detail: String) {
        stop()
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(TimeInterval(seconds))
        self.workout = workout
        self.title = title
        self.detail = detail
        startActivity()
        scheduleNotification()
        watch()
    }

    /// adjustRest(±15): flytter sluttidspunktet. Gør intet, hvis timeren ikke kører.
    func adjust(_ seconds: Int) {
        guard let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        endDate = newEnd
        if newEnd <= Date() {
            // Den planlagte notifikation gælder det gamle tidspunkt, så den fjernes.
            stop()
            Self.vibrate()
            return
        }
        updateActivity()
        scheduleNotification()
    }

    /// stopTimer()
    func stop() {
        stop(removeNotification: true)
    }

    private func stop(removeNotification: Bool) {
        watcher?.cancel()
        watcher = nil
        startDate = nil
        endDate = nil
        if removeNotification {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        }
        endAllActivities()
    }

    /// Kaldes når appen kommer i forgrunden igen: stop en pause, der er udløbet i mellemtiden.
    func checkExpired() {
        if let end = endDate, end <= Date() {
            complete()
        } else if endDate == nil {
            endAllActivities()
        }
    }

    /// Pausen er slut: appen vibrerer, notifikationen får lov at komme, resten ryddes.
    private func complete() {
        stop(removeNotification: false)
        Self.vibrate()
    }

    /// navigator.vibrate(...) i webappen: en rigtig vibration, ingen lyd.
    static func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func watch() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if let end = self.endDate, end <= Date() {
                    self.complete()
                    return
                }
            }
        }
    }

    // MARK: - Live Activity

    private var state: RestActivityAttributes.ContentState? {
        guard let startDate, let endDate else { return nil }
        return RestActivityAttributes.ContentState(
            startDate: startDate, endDate: endDate, title: title, detail: detail
        )
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state else { return }
        do {
            activity = try Activity<RestActivityAttributes>.request(
                attributes: RestActivityAttributes(workout: workout),
                content: ActivityContent(state: state, staleDate: state.endDate),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    private func updateActivity() {
        guard let activity, let state else { return }
        let content = ActivityContent(state: state, staleDate: state.endDate)
        Task {
            await activity.update(content)
        }
    }

    private func endAllActivities() {
        activity = nil
        for a in Activity<RestActivityAttributes>.activities {
            Task {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Notifikation

    private func scheduleNotification() {
        guard let endDate else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        let interval = max(1, endDate.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "Pausen er slut"
        content.body = title + (detail.isEmpty ? "" : " · " + detail)
        // Lyd er nødvendig for at telefonen vibrerer, når appen ikke er åben.
        // På lydløs vibrerer den kun.
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger), withCompletionHandler: nil)
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
