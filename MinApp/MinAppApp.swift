import SwiftData
import SwiftUI
import UserNotifications

@main
@MainActor
struct MinAppApp: App {
    private let container: ModelContainer
    @State private var store: TrainingStore

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: ExerciseProgress.self, WorkoutLog.self, CustomExercise.self, AppSettings.self
            )
        } catch {
            fatalError("Kunne ikke åbne databasen: \(error)")
        }
        self.container = container
        let store = TrainingStore(context: container.mainContext)
        _store = State(initialValue: store)

        // Knapperne i Live Activity (App Intents) kører i appens proces.
        RestIntentBridge.completeSet = { [weak store] in store?.completeNextSet() }
        RestIntentBridge.addTime = { [weak store] sec in store?.timer.adjust(sec) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in store.applyQuick(url) }
        }
        .modelContainer(container)
    }
}
