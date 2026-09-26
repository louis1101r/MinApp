import SwiftUI

struct RootView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var route: Route?

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
                    .padding(.bottom, store.timers.anyRunning ? CGFloat(40 + 50 * store.timers.running.count) : 30)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // Ny skærm starter øverst, som window.scrollTo(0,0) i webappen.
            .id(screenKey)
            .overlay(alignment: .bottom) { floating }
            NavBar()
        }
        .background(T.bg.ignoresSafeArea())
        .onAppear {
            RestTimers.requestNotificationPermission()
            store.appDidBecomeActive()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.appDidBecomeActive() }
        }
        .sheet(item: $route) { r in
            RouteSheet(route: r)
        }
        .environment(\.present, PresentAction { route = $0 })
    }

    /// Toast og hviletimer over navigationen.
    private var floating: some View {
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
            ForEach(store.timers.runningProfiles, id: \.self) { p in
                TimerPill(profile: p)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 12)
        .animation(.easeOut(duration: 0.22), value: store.toastMessage)
        .animation(.easeOut(duration: 0.22), value: store.timers.runningProfiles)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Træningsregistrering")
                .font(.system(size: 15, weight: .heavy))
                .tracking(-0.3)
            Spacer()
            Text(store.isLoaded ? "\(store.logCount(.louis)) træninger" : "Indlæser…")
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
        switch store.tab {
        case .home:
            return store.finishGroups != nil ? "finish" : (store.active != nil ? "session" : "home")
        case .hist:
            return "hist"
        case .set:
            return "set"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.tab {
        case .home:
            if let groups = store.finishGroups {
                FinishView(groups: groups)
            } else if store.active != nil {
                SessionView()
            } else {
                HomeView()
            }
        case .hist:
            HistoryView()
        case .set:
            ProgramView()
        }
    }
}

/// nav: Træning · Udvikling · Program
struct NavBar: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            item("Træning", .home)
            Rectangle().fill(T.hair).frame(width: 1)
            item("Udvikling", .hist)
            Rectangle().fill(T.hair).frame(width: 1)
            item("Program", .set)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: T.maxWidth)
        .frame(maxWidth: .infinity)
        .background(T.bg)
        .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 2) }
    }

    private func item(_ label: String, _ t: Tab) -> some View {
        let on = store.tab == t
        return Button {
            hideKeyboard()
            withAnimation(.easeOut(duration: 0.18)) {
                // go(t): slutskærmen forsvinder, når man skifter fane.
                store.finishGroups = nil
                store.tab = t
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? T.ink : T.muted)
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(alignment: .top) {
                    if on { Rectangle().fill(T.ink).frame(height: 3).padding(.top, 2) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Ark

/// De ark, webappen viser med showSheet().
enum Route: Identifiable {
    case info(String)
    case rir
    case swap(String, inSession: Bool)
    case pickerGroup(String)
    case pickerSession
    case create(group: String, toSession: Bool)
    case stats(String)

    var id: String {
        switch self {
        case .info(let id): return "info-" + id
        case .rir: return "rir"
        case .swap(let id, let s): return "swap-\(id)-\(s)"
        case .pickerGroup(let g): return "picker-" + g
        case .pickerSession: return "picker-session"
        case .create(let g, let s): return "create-\(g)-\(s)"
        case .stats(let id): return "stats-" + id
        }
    }
}

/// Visninger, der skubbes ind i et ark (ⓘ fra en liste, "Opret ny øvelse" fra tilføj).
enum SheetPush: Hashable {
    case info(String)
    case create(group: String, toSession: Bool)
}

struct PresentAction {
    var action: (Route) -> Void
    init(_ action: @escaping (Route) -> Void = { _ in }) {
        self.action = action
    }
    func callAsFunction(_ r: Route) {
        action(r)
    }
}

private struct PresentKey: EnvironmentKey {
    static let defaultValue = PresentAction()
}

extension EnvironmentValues {
    var present: PresentAction {
        get { self[PresentKey.self] }
        set { self[PresentKey.self] = newValue }
    }
}

/// Luk hele arket (også fra en visning, der er skubbet ind).
struct CloseSheetAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

private struct CloseSheetKey: EnvironmentKey {
    static let defaultValue = CloseSheetAction()
}

extension EnvironmentValues {
    var closeSheet: CloseSheetAction {
        get { self[CloseSheetKey.self] }
        set { self[CloseSheetKey.self] = newValue }
    }
}

struct RouteSheet: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            root
                .navigationDestination(for: SheetPush.self) { p in
                    switch p {
                    case .info(let id):
                        ExerciseInfoView(id: id, pushed: true)
                    case .create(let g, let s):
                        CreateExerciseView(group: g, toSession: s, pushed: true)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Færdig") { hideKeyboard() }
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
        }
        .environment(\.closeSheet, CloseSheetAction { dismiss() })
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(0)
        .tint(T.blue)
    }

    @ViewBuilder
    private var root: some View {
        switch route {
        case .info(let id):
            ExerciseInfoView(id: id)
        case .rir:
            RIRInfoView()
        case .swap(let id, let inSession):
            SwapView(id: id, inSession: inSession)
        case .pickerGroup(let g):
            PickerView(group: g)
        case .pickerSession:
            PickerView(group: nil)
        case .create(let g, let s):
            CreateExerciseView(group: g, toSession: s, pushed: false)
        case .stats(let id):
            StatsView(id: id)
        }
    }
}

// MARK: - Timer

/// .timer .pill: −15 · 0:00 · +15 · Stop (én per person, med navn når I træner sammen)
struct TimerPill: View {
    @Environment(TrainingStore.self) private var store
    let profile: Profile

    var body: some View {
        let t = store.timers
        HStack(spacing: 14) {
            if t.together {
                Text(t.displayName(profile))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: 70, alignment: .leading)
            }
            Button("−15") { t.adjust(profile, -15) }
                .font(.system(size: 13, weight: .bold))
                .opacity(0.85)
            if let r = t.running[profile], r.end > r.start {
                Text(timerInterval: r.start...r.end, countsDown: true)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            Button("+15") { t.adjust(profile, 15) }
                .font(.system(size: 13, weight: .bold))
                .opacity(0.85)
            Button("Stop") { t.stop(profile) }
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
