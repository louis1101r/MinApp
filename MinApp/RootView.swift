import SwiftUI

struct RootView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var infoId: InfoTarget?

    var body: some View {
        // NavigationStack kun for at tastaturets "Færdig"-knap virker; navigationslinjen er skjult.
        NavigationStack {
            main
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Færdig") { hideKeyboard() }
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
        }
        .tint(T.blue)
    }

    private var main: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .frame(maxWidth: T.maxWidth)
                    .padding(.horizontal, 18)
                    .padding(.bottom, store.timer.isRunning ? 110 : 40)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // Ny skærm starter øverst, som window.scrollTo(0,0) i webappen.
            .id(screenKey)
        }
        .background(T.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let msg = store.toastMessage {
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(T.onInk)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(T.ink)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if store.timer.isRunning {
                    TimerPill()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 12)
            .animation(.easeOut(duration: 0.22), value: store.toastMessage)
            .animation(.easeOut(duration: 0.22), value: store.timer.isRunning)
        }
        .onAppear {
            RestTimer.requestNotificationPermission()
            store.timer.checkExpired()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.timer.checkExpired() }
        }
        .sheet(item: $infoId) { target in
            switch target {
            case .exercise(let id):
                ExerciseInfoView(id: id)
            case .rir:
                RIRInfoView()
            }
        }
        .environment(\.showInfo, ShowInfoAction { infoId = $0 })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Træningsregistrering")
                .font(.system(size: 15, weight: .heavy))
                .tracking(-0.3)
            Spacer()
            Text("\(store.log.count) træninger")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(T.muted)
        }
        .foregroundStyle(T.ink)
        .frame(maxWidth: T.maxWidth)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(T.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.line).frame(height: 2)
        }
    }

    private var screenKey: String {
        store.adjustments != nil ? "finish" : (store.active != nil ? "session" : "home")
    }

    @ViewBuilder
    private var content: some View {
        if let adj = store.adjustments {
            FinishView(adjustments: adj)
                .transition(.opacity)
        } else if store.active != nil {
            SessionView()
                .transition(.opacity)
        } else {
            HomeView()
                .transition(.opacity)
        }
    }
}

// MARK: - Info-ark

enum InfoTarget: Identifiable, Hashable {
    case exercise(String)
    case rir

    var id: String {
        switch self {
        case .exercise(let id): return "ex-" + id
        case .rir: return "rir"
        }
    }
}

struct ShowInfoAction {
    var action: (InfoTarget) -> Void
    init(_ action: @escaping (InfoTarget) -> Void = { _ in }) {
        self.action = action
    }
    func callAsFunction(_ t: InfoTarget) {
        action(t)
    }
}

private struct ShowInfoKey: EnvironmentKey {
    static let defaultValue = ShowInfoAction()
}

extension EnvironmentValues {
    var showInfo: ShowInfoAction {
        get { self[ShowInfoKey.self] }
        set { self[ShowInfoKey.self] = newValue }
    }
}

// MARK: - Timer

/// .timer .pill: −15 · 0:00 · +15 · Stop
struct TimerPill: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Button("−15") { store.timer.adjust(-15) }
                .font(.system(size: 13, weight: .bold))
                .opacity(0.85)
            if let start = store.timer.startDate, let end = store.timer.endDate, end > start {
                Text(timerInterval: start...end, countsDown: true)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            Button("+15") { store.timer.adjust(15) }
                .font(.system(size: 13, weight: .bold))
                .opacity(0.85)
            Button("Stop") { store.timer.stop() }
                .font(.system(size: 16, weight: .semibold))
                .opacity(0.8)
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(T.blue)
    }
}
