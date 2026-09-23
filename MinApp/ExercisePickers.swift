import SwiftUI

/// exListItem(): navn + meta, og ⓘ der viser beskrivelsen med "Tilbage".
struct ExerciseListRow: View {
    @Environment(TrainingStore.self) private var store
    let id: String
    let meta: String
    var disabled = false
    var current = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name(id))
                        .font(.system(size: 16, weight: current ? .bold : .regular))
                        .foregroundStyle(T.ink)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.99))
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            NavigationLink(value: SheetPush.info(id)) {
                Text("ⓘ")
                    .font(.system(size: 15))
                    .foregroundStyle(T.muted)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Om øvelsen")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
    }
}

/// Søgefelt (filterSwap).
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text("Søg øvelse…").foregroundColor(Color(white: 0.69)))
            .font(.system(size: 16, weight: .semibold))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(T.wash)
            .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))
    }
}

@MainActor
private func matches(_ store: TrainingStore, _ id: String, _ q: String) -> Bool {
    let t = q.trimmingCharacters(in: .whitespaces).lowercased()
    return t.isEmpty || store.name(id).lowercased().contains(t)
}

/// openSwap(id, inSession) → doSwap(nid)
struct SwapView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.closeSheet) private var closeSheet
    let id: String
    let inSession: Bool
    @State private var query = ""

    var body: some View {
        let g = store.tgOf(id)
        let keys = store.exKeys
        let list = keys.filter { store.tgOf($0) == g }
        let rest = store.byGroupOrder(keys.filter { store.tgOf($0) != g })

        InfoSheet(title: "Byt øvelse", close: { closeSheet() }) {
            Text("Samme muskelgruppe holder programmets balance. Vægten følger med den nye øvelse fra første logning.")
                .leadStyle()
                .padding(.top, 8)
                .padding(.bottom, 12)
            SearchField(text: $query)
            InfoHeading(text: g)
            ForEach(list.filter { matches(store, $0, query) }, id: \.self) { k in
                row(k)
            }
            InfoHeading(text: "Andre muskelgrupper")
                .padding(.top, 6)
            ForEach(rest.filter { matches(store, $0, query) }, id: \.self) { k in
                row(k)
            }
        }
    }

    private func row(_ k: String) -> some View {
        let x = store.EX(k)
        let meta = "\(x?.m ?? "") · \(x?.lo ?? 0)–\(x?.hi ?? 0) gentagelser" + (k == id ? " · valgt nu" : "")
        return ExerciseListRow(id: k, meta: meta, current: k == id) {
            store.doSwap(old: id, new: k, inSession: inSession)
            closeSheet()
        }
    }
}

/// openPicker("group", g) / openPicker("session") → pickAdd(k)
struct PickerView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.closeSheet) private var closeSheet
    /// nil = dagens træning.
    let group: String?
    @State private var query = ""

    var body: some View {
        let inList = group.map { store.groupList($0) } ?? (store.active?.ex.map(\.id) ?? [])
        let focus = group.map { [$0] } ?? store.sessionFocus
        let keys = store.exKeys
        let first = stableByFocus(keys.filter { focus.contains(store.tgOf($0)) }, focus)
        let rest = store.byGroupOrder(keys.filter { !focus.contains(store.tgOf($0)) })
        let createGroup = group ?? (focus.first ?? "Bryst")

        InfoSheet(title: group.map { "Tilføj til " + $0 } ?? "Tilføj øvelse", close: { closeSheet() }) {
            Text(group.map { "Øvelsen lægges nederst i \($0). Du kan flytte den op bagefter." }
                 ?? "Øvelsen lægges til dagens træning.")
                .leadStyle()
                .padding(.top, 8)
                .padding(.bottom, 14)
            NavigationLink(value: SheetPush.create(group: createGroup, toSession: group == nil)) {
                Text("+ Opret ny øvelse")
            }
            .buttonStyle(BlockButtonStyle(outline: true, small: true))
            SearchField(text: $query)
                .padding(.top, 12)
                .padding(.bottom, 6)
            if !first.isEmpty {
                InfoHeading(text: focus.joined(separator: " + "))
                ForEach(first.filter { matches(store, $0, query) }, id: \.self) { k in
                    row(k, has: inList.contains(k))
                }
            }
            InfoHeading(text: "Andre muskelgrupper")
                .padding(.top, 6)
            ForEach(rest.filter { matches(store, $0, query) }, id: \.self) { k in
                row(k, has: inList.contains(k))
            }
        }
    }

    /// Sortering efter fokusgruppernes rækkefølge (stabil).
    private func stableByFocus(_ ids: [String], _ focus: [String]) -> [String] {
        ids.enumerated()
            .sorted { a, b in
                let ka = focus.firstIndex(of: store.tgOf(a.element)) ?? -1
                let kb = focus.firstIndex(of: store.tgOf(b.element)) ?? -1
                return ka != kb ? ka < kb : a.offset < b.offset
            }
            .map(\.element)
    }

    private func row(_ k: String, has: Bool) -> some View {
        let x = store.EX(k)
        let meta = "\(x?.m ?? "") · \(x?.lo ?? 0)–\(x?.hi ?? 0) gentagelser" + (has ? " · allerede med" : "")
        return ExerciseListRow(id: k, meta: meta, disabled: has) {
            if let group {
                store.addToGroup(k, group)
            } else {
                store.addToSession(k)
            }
            closeSheet()
        }
    }
}

/// openCreate(group, toSession) → doCreate()
struct CreateExerciseView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.closeSheet) private var closeSheet
    @Environment(\.dismiss) private var dismiss
    let toSession: Bool
    let pushed: Bool
    @State private var f: TrainingStore.NewExercise

    init(group: String, toSession: Bool, pushed: Bool) {
        self.toSession = toSession
        self.pushed = pushed
        _f = State(initialValue: TrainingStore.NewExercise(
            name: "", group: group, lo: "8", hi: "12", sets: "3", rest: "90", desc: ""
        ))
    }

    var body: some View {
        InfoSheet(title: "Ny øvelse", closeLabel: pushed ? "Tilbage" : "Luk", close: { dismiss() }) {
            Text(toSession
                 ? "Øvelsen lægges i den valgte muskelgruppe og tilføjes til dagens træning."
                 : "Øvelsen lægges nederst i den valgte muskelgruppe.")
                .leadStyle()
                .padding(.top, 8)

            label("Navn")
            TextField("", text: $f.name, prompt: Text("Fx Kabeltræk, skrå").foregroundColor(Color(white: 0.69)))
                .font(.system(size: 16, weight: .semibold))
                .padding(12)
                .background(T.wash)
                .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))
                .onChange(of: f.name) { _, v in
                    if v.count > 60 { f.name = String(v.prefix(60)) }
                }

            label("Muskelgruppe")
            Menu {
                Picker("Muskelgruppe", selection: $f.group) {
                    ForEach(Catalog.tg, id: \.self) { g in
                        Text(g).tag(g)
                    }
                }
            } label: {
                HStack {
                    Text(f.group)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("▾")
                }
                .foregroundStyle(T.ink)
                .padding(13)
                .overlay(Rectangle().strokeBorder(T.ink, lineWidth: 2))
                .contentShape(Rectangle())
            }

            HStack(spacing: 10) {
                field("Min. gentagelser", $f.lo)
                field("Maks. gentagelser", $f.hi)
            }
            HStack(spacing: 10) {
                field("Sæt", $f.sets)
                field("Pause (sek.)", $f.rest)
            }

            label("Beskrivelse (valgfri)")
            TextField("", text: $f.desc, prompt: Text("Udgangsstilling, udførelse, fokuspunkter…").foregroundColor(Color(white: 0.69)), axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(5...12)
                .padding(12)
                .background(T.wash)
                .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))

            Button("Opret øvelse") {
                hideKeyboard()
                if store.doCreate(f, toSession: toSession) {
                    closeSheet()
                }
            }
            .buttonStyle(BlockButtonStyle())
            .padding(.top, 20)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .smallMuted()
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label(title)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .padding(.vertical, 12)
                .background(T.wash)
                .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
