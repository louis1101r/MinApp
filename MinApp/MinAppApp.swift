import SwiftData
import SwiftUI
import UserNotifications

@main
@MainActor
struct MinAppApp: App {
    private let container: ModelContainer?
    private let openError: String?
    @State private var store: TrainingStore?

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Kopi af databasen, før v4-skemaet åbner (og ændrer) den første gang.
        BackupFiles.copyDatabaseBeforeV4()
        do {
            let container = try ModelContainer(
                for: ExerciseProgress.self, ProfileProgress.self, WorkoutLog.self, CustomExercise.self, AppSettings.self
            )
            self.container = container
            self.openError = nil
            let store = TrainingStore(container: container)
            _store = State(initialValue: store)

            // Knapperne i Live Activity (App Intents) kører i appens proces.
            RestIntentBridge.completeSet = { [weak store] raw in
                if let p = Profile(rawValue: raw) { store?.completeNextSet(p) }
            }
            RestIntentBridge.addTime = { [weak store] raw, sec in
                if let p = Profile(rawValue: raw) { store?.timers.adjust(p, sec) }
            }
        } catch {
            // Ingen crash: vis fejlen, så data på disken ikke røres.
            self.container = nil
            self.openError = String(describing: error)
            _store = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store, let container {
                RootView()
                    .environment(store)
                    .modelContainer(container)
                    .onOpenURL { url in store.applyQuick(url) }
            } else {
                DatabaseErrorView(message: openError ?? "")
            }
        }
    }
}

/// Vises kun, hvis databasen ikke kan åbnes. Dine data og backupfiler ligger urørt.
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Databasen kunne ikke åbnes")
                    .displayStyle(28)
                Text("Dine data er ikke slettet. En kopi ligger i Filer under På min iPhone → MinApp. Send fejlteksten herunder videre, så kan det rettes.")
                    .leadStyle()
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(T.muted)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(maxWidth: T.maxWidth, alignment: .leading)
        }
        .background(T.bg.ignoresSafeArea())
    }
}
