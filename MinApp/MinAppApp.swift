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
        _store = State(initialValue: TrainingStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
