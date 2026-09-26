import SwiftUI
import UIKit

/// viewSession(): igangværende træning med sæt-tabel, ✓-knap og pause.
/// Træner I sammen, har hvert sæt en række per person.
struct SessionView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.present) private var present
    @State private var confirmCancel = false

    var body: some View {
        if let a = store.active {
            let all = a.ex.flatMap { e in e.people.values.flatMap(\.sets) }
            let totalSets = all.count
            let doneSets = all.filter(\.done).count
            let pct = totalSets > 0 ? Double(doneSets) / Double(totalSets) : 0

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(a.name)
                        .displayStyle(30)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Afbryd") { confirmCancel = true }
                        .buttonStyle(TextLinkStyle(color: T.red))
                }
                if a.together {
                    Text("Sammen: " + a.profiles.map { store.name(of: $0) }.joined(separator: " og "))
                        .leadStyle()
                        .padding(.top, 4)
                }
                ProgressBar(value: pct)
                    .padding(.top, 16)
                Text("\(doneSets) af \(totalSets) sæt")
                    .smallMuted()
                    .monospacedDigit()
                    .padding(.top, 8)

                if a.ex.isEmpty {
                    Text("Der er ingen øvelser i dagens træning. Tilføj en herunder.")
                        .leadStyle()
                        .padding(.vertical, 24)
                }

                ForEach(Array(a.ex.enumerated()), id: \.offset) { i, e in
                    ExerciseBlock(i: i, e: e, profiles: a.profiles)
                }

                Button("+ Tilføj øvelse") {
                    hideKeyboard()
                    present(.pickerSession)
                }
                .buttonStyle(BlockButtonStyle(outline: true))
                .padding(.top, 22)

                Button(store.isLoaded ? "Afslut og opdatér vægtene" : "Indlæser…") {
                    hideKeyboard()
                    withAnimation(.easeOut(duration: 0.18)) { store.finish() }
                }
                .buttonStyle(BlockButtonStyle())
                .disabled(!store.isLoaded)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .padding(.top, 20)
            .confirmationDialog("Afbryd træning?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Kassér træningen", role: .destructive) {
                    withAnimation(.easeOut(duration: 0.18)) { store.cancelSession() }
                }
                Button("Annuller", role: .cancel) {}
            } message: {
                Text("Din fremgang i denne træning bliver ikke gemt.")
            }
        }
    }
}

/// .progress .fill
struct ProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(T.hair)
                Rectangle().fill(T.blue)
                    .frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .animation(.easeOut(duration: 0.35), value: value)
    }
}

/// Én øvelse (.ex) med sæt-tabellen.
struct ExerciseBlock: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.present) private var present
    @State private var confirmRemove = false
    let i: Int
    let e: ActiveExercise
    let profiles: [Profile]

    private var together: Bool { profiles.count > 1 }

    var body: some View {
        let x = store.EX(e.id)
        let maxSets = profiles.map { e[$0]?.sets.count ?? 0 }.max() ?? 0
        let stalledNames = profiles.filter { store.stall(e.id, $0) >= 1 }.map { store.name(of: $0) }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(store.name(e.id))
                            .font(.system(size: 19, weight: .bold))
                            .tracking(-0.4)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            present(.info(e.id))
                        } label: {
                            Text("ⓘ")
                                .font(.system(size: 15))
                                .foregroundStyle(T.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Om øvelsen")
                    }
                    if let x {
                        ForEach(profiles, id: \.self) { p in
                            if let person = e[p] {
                                Text(targetText(x, person, p))
                                    .font(.system(size: 13))
                                    .monospacedDigit()
                                    .foregroundStyle(T.muted)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if !stalledNames.isEmpty {
                    Text(together ? "⚠ stagneret: " + stalledNames.joined(separator: ", ") : "⚠ stagneret")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(T.red)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.top, 4)
                }
                Button {
                    hideKeyboard()
                    if store.hasLogged(i) {
                        confirmRemove = true
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { store.removeFromSession(i) }
                    }
                } label: {
                    Text("✕")
                        .font(.system(size: 15))
                        .foregroundStyle(T.muted)
                        .frame(width: 40, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fjern fra dagens træning")
                .padding(.top, -6)
                .padding(.trailing, -10)
            }

            SetHeader(together: together)
                .padding(.top, 14)

            ForEach(0..<maxSets, id: \.self) { j in
                if together && j > 0 {
                    Rectangle().fill(T.hair).frame(height: 1).padding(.vertical, 4)
                }
                ForEach(profiles, id: \.self) { p in
                    if let person = e[p], person.sets.indices.contains(j) {
                        SetRow(
                            i: i, j: j, profile: p,
                            label: rowLabel(j, p),
                            together: together,
                            set: person.sets[j], target: person.target, hi: x?.hi ?? 0
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Ekstra sæt") { store.addSet(i) }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
                if let x {
                    Button(pauseLabel(x.r)) {
                        hideKeyboard()
                        store.manualRest(i)
                    }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
                }
                Button("Byt") {
                    hideKeyboard()
                    present(.swap(e.id, inSession: true))
                }
                .buttonStyle(BlockButtonStyle(outline: true, small: true))
            }
            .padding(.top, 12)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(T.hair).frame(height: 1) }
        .padding(.top, 18)
        .confirmationDialog("Fjern \(store.name(e.id))?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Fjern øvelsen", role: .destructive) {
                withAnimation(.easeOut(duration: 0.18)) { store.removeFromSession(i) }
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("Det, du har logget på øvelsen i dag, bliver ikke gemt.")
        }
    }

    /// Sætnummer, og ved træn sammen også navnet ("1 Louis" / "Anna").
    private func rowLabel(_ j: Int, _ p: Profile) -> String {
        if !together { return "\(j + 1)" }
        let first = p == profiles.first
        return (first ? "\(j + 1) " : "") + store.name(of: p)
    }

    private func targetText(_ x: ExerciseDef, _ person: ActivePerson, _ p: Profile) -> String {
        let prefix = together ? store.name(of: p) + ": " : ""
        if let t = person.target {
            return prefix + "\(person.sets.count) × \(x.lo)–\(x.hi) ved \(fmt(t)) kg"
        }
        return prefix + "Vælg en vægt du kan tage \(x.lo)–\(x.hi) gange med 2 i tanken"
    }

    /// "Pause " + Math.round(r/6)/10 + " min"
    private func pauseLabel(_ r: Int) -> String {
        let tenths = (Double(r) / 6 + 0.5).rounded(.down)
        return "Pause " + fmt(tenths / 10) + " min"
    }
}

private enum Col {
    static let index: CGFloat = 22
    static let name: CGFloat = 64
    static let tick: CGFloat = 52
    static let gap: CGFloat = 6
}

struct SetHeader: View {
    @Environment(\.present) private var present
    var together = false

    var body: some View {
        HStack(spacing: Col.gap) {
            Color.clear.frame(width: together ? Col.name : Col.index, height: 1)
            headerText("kg")
            headerText("gentagelser")
            Button {
                present(.rir)
            } label: {
                HStack(spacing: 2) {
                    Text("i tanken")
                    Text("ⓘ")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(T.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: Col.tick, height: 1)
        }
        .padding(.bottom, 6)
    }

    private func headerText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(T.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
}

struct SetRow: View {
    @Environment(TrainingStore.self) private var store
    let i: Int
    let j: Int
    let profile: Profile
    let label: String
    let together: Bool
    let set: ActiveSet
    let target: Double?
    let hi: Int

    var body: some View {
        HStack(spacing: Col.gap) {
            Text(label)
                .font(.system(size: together ? 12 : 13, weight: together ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(T.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: together ? Col.name : Col.index, alignment: .leading)
            NumberField(
                text: binding(\.w),
                placeholder: target.map { fmt($0) } ?? "",
                keyboard: .decimalPad,
                done: set.done
            )
            NumberField(text: binding(\.r), placeholder: "\(hi)", keyboard: .numberPad, done: set.done)
            NumberField(text: binding(\.rir), placeholder: "2", keyboard: .numberPad, done: set.done)
            Button {
                hideKeyboard()
                withAnimation(.easeOut(duration: 0.15)) { store.tick(i, profile, j) }
            } label: {
                Text(set.done ? "✓" : "○")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: Col.tick, height: 44)
                    .foregroundStyle(set.done ? T.onInk : T.ink)
                    .background(set.done ? T.ink : T.wash)
                    .overlay(Rectangle().strokeBorder(set.done ? T.ink : T.hair, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
            .accessibilityLabel(set.done ? "Sæt færdigt" : "Markér sæt færdigt")
        }
        .padding(.vertical, 3)
    }

    private func binding(_ k: WritableKeyPath<ActiveSet, String>) -> Binding<String> {
        Binding(
            get: { store.value(i, profile, j, k) },
            set: { store.setVal(i, profile, j, k, $0) }
        )
    }
}

/// input[type=number] i webappens stil.
struct NumberField: View {
    @Binding var text: String
    let placeholder: String
    let keyboard: UIKeyboardType
    let done: Bool
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(white: 0.69)))
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(T.ink)
            .focused($focused)
            .padding(.vertical, 12)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(focused || done ? T.bg : T.wash)
            .overlay(
                Rectangle().strokeBorder(focused ? T.blue : (done ? T.ink : T.hair), lineWidth: focused || done ? 2 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: done)
    }
}
