import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// viewProg(): muskelgrupper og øvelser, egne øvelser, favoritter, vægtspring, "Sådan regner den" og data.
struct ProgramView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.present) private var present
    @State private var incU = ""
    @State private var incL = ""
    @State private var pendingImport: BackupData?
    @State private var confirmWipe = false
    @State private var showFileImporter = false
    @State private var shareFile: ShareFile?
    @State private var buddyName = ""
    @State private var busy = false

    var body: some View {
        let last = store.lastTrained()

        VStack(alignment: .leading, spacing: 0) {
            Text("Dit program")
                .displayStyle(28)
            Text("Hver muskelgruppe har sine øvelser. Når du kombinerer flere grupper, bruges de øverste først. Tryk på en øvelse for at bytte den.")
                .leadStyle()
                .padding(.top, 8)

            ForEach(Catalog.tg, id: \.self) { g in
                groupSection(g, last: last)
            }

            Sec {
                SectionTitle(text: "Træningsmakker")
                Text("Navnet bruges, når I træner sammen. Makkerens vægte, log og grafer holdes adskilt fra dine.")
                    .smallMuted()
                TextField("", text: $buddyName, prompt: Text("Makker").foregroundColor(Color(white: 0.69)))
                    .font(.system(size: 16, weight: .semibold))
                    .padding(12)
                    .background(T.wash)
                    .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))
                    .onSubmit { store.setBuddyName(buddyName) }
                    .onChange(of: buddyName) { _, v in store.setBuddyName(v) }
            }

            Sec {
                SectionTitle(text: "Egne øvelser")
                Text("Mangler en øvelse? Opret den selv med dit eget rep-interval og din egen beskrivelse.")
                    .smallMuted()
                Button("+ Opret ny øvelse") { present(.create(group: "Bryst", toSession: false)) }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
                    .padding(.top, 2)
            }

            if !store.favs.isEmpty {
                Sec {
                    SectionTitle(text: "Favoritter")
                    VStack(spacing: 0) {
                        ForEach(Array(store.favs.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 0) {
                                Text(f.joined(separator: " + "))
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.vertical, 4)
                                IconButton(symbol: "✕", label: "Fjern favorit") { store.removeFav(i) }
                            }
                            .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
                        }
                    }
                }
            }

            Sec {
                SectionTitle(text: "Mindste vægtspring")
                HStack(spacing: 10) {
                    incField("Overkrop", $incU) { store.setInc(upper: true, $0) }
                    incField("Underkrop", $incL) { store.setInc(upper: false, $0) }
                }
                Text("Sæt dem lavt, hvis du har mikroskiver. Mindre spring betyder længere tid, før du går i stå.")
                    .smallMuted()
                    .padding(.top, 2)
            }

            Sec {
                SectionTitle(text: "Sådan regner den")
                Text("Anbefalingen: appen foreslår det par (Bryst + Triceps, Ryg + Biceps, Ben, Skulder + Mave), hvor musklerne har hvilet længst.")
                    .font(.system(size: 13))
                Text(verbatim: "Alle sæt i toppen af intervallet med 0–2 i tanken: vægten op ét spring. Med 3 eller flere i tanken: to spring, fordi du undervurderede dig selv. Inden for intervallet: samme vægt, flere gentagelser. Under intervallet to gange i træk: 10 % ned. Tre stigninger i træk på en frisk dag giver et ekstra sæt, med loft to over udgangspunktet.")
                    .font(.system(size: 13))
                Text(verbatim: "Dagsformen skalerer belastningen: slidt −10 % og et sæt færre, træt −5 %, topform +2,5 %.")
                    .font(.system(size: 13))
            }

            dataSection
        }
        .foregroundStyle(T.ink)
        .padding(.top, 22)
        .onAppear {
            incU = fmtInput(store.settings.incU)
            incL = fmtInput(store.settings.incL)
            buddyName = store.settings.buddyName
        }
        .confirmationDialog(
            "Gendan backup?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { b in
            if b.buddy == nil {
                Button("Gendan og behold \(store.name(of: .buddy))s data", role: .destructive) {
                    restore(b, keepBuddy: true)
                }
                Button("Gendan og slet \(store.name(of: .buddy))s data", role: .destructive) {
                    restore(b, keepBuddy: false)
                }
            } else {
                Button("Overskriv og gendan", role: .destructive) {
                    restore(b, keepBuddy: false)
                }
            }
            Button("Annuller", role: .cancel) { pendingImport = nil }
        } message: { b in
            Text(importSummary(b))
        }
        .confirmationDialog("Slet alt?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Slet alt", role: .destructive) {
                store.wipe()
                refreshFields()
            }
            Button("Annuller", role: .cancel) {}
        } message: {
            Text("Alle træninger, vægte og øvelser, du har tilføjet, forsvinder permanent – også makkerens. Det kan ikke fortrydes.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                readBackup(data)
            } else {
                store.toast("Kunne ikke læse filen.")
            }
        }
        .sheet(item: $shareFile) { f in
            ActivityView(items: [f.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - muskelgrupper

    private func groupSection(_ g: String, last: [String: Double]) -> some View {
        let L = store.groupList(g)
        let when = last[g].map { "sidst " + store.agoTxt($0) } ?? "ikke trænet endnu"
        return Sec {
            Text("\(Text(g).bold()) \(Text("· " + when).foregroundColor(T.muted))")
                .font(.system(size: 13))
            if L.isEmpty {
                Text("Ingen øvelser endnu. Gruppen kan ikke vælges, før du tilføjer en.")
                    .smallMuted()
            }
            VStack(spacing: 0) {
                ForEach(Array(L.enumerated()), id: \.element) { i, id in
                    progRow(id, g, i)
                }
            }
            if L.count > store.capFor(g, 2) {
                Text("Sammen med én anden gruppe bruges de øverste \(store.capFor(g, 2)).")
                    .smallMuted()
                    .padding(.top, 2)
            }
            Button("+ Tilføj øvelse til " + g) { present(.pickerGroup(g)) }
                .buttonStyle(TextLinkStyle())
        }
    }

    private func progRow(_ id: String, _ g: String, _ i: Int) -> some View {
        let x = store.EX(id)
        let w = store.stW(id)
        var weight = " · ingen vægt endnu"
        if let w, w != 0 { weight = " · " + fmt(w) + " kg" }
        if let bw = store.stW(id, .buddy), bw != 0 {
            weight += " · " + store.name(of: .buddy) + " " + fmt(bw) + " kg"
        }
        let meta: String = "\(store.stSets(id)) × \(x?.lo ?? 0)–\(x?.hi ?? 0)" + weight
        return HStack(spacing: 0) {
            Button {
                present(.swap(id, inSession: false))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name(id))
                        .font(.system(size: 16))
                        .foregroundStyle(T.ink)
                    Text(meta)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.99))
            IconButton(symbol: "ⓘ", label: "Om øvelsen") { present(.info(id)) }
            IconButton(symbol: "↑", label: "Flyt op", disabled: i == 0) { store.moveEx(g, i) }
            IconButton(symbol: "✕", label: "Fjern fra " + g) { store.removeFromGroup(g, i) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
    }

    private func incField(_ title: String, _ text: Binding<String>, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).smallMuted()
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .padding(.vertical, 12)
                .background(T.wash)
                .overlay(Rectangle().strokeBorder(T.hair, lineWidth: 1))
                .onChange(of: text.wrappedValue) { _, v in onChange(v) }
        }
        .frame(maxWidth: .infinity)
    }

    private func fmtInput(_ v: Double) -> String {
        fmt(v)
    }

    // MARK: - data

    private var dataSection: some View {
        Sec {
            SectionTitle(text: "Data")
            Text("Backuppen har samme format som webappens \"Kopiér backup\" (med makkeren som ekstra felt), så den kan gendannes begge steder. Automatiske backups ligger i Filer under På min iPhone → MinApp.")
                .smallMuted()
            HStack(spacing: 10) {
                Button("Kopiér backup") {
                    run {
                        let data = await store.exportData()
                        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
                        store.toast("Kopieret til udklipsholder.")
                    }
                }
                .buttonStyle(BlockButtonStyle(outline: true, small: true))
                Button("Indsæt backup") {
                    guard let s = UIPasteboard.general.string, !s.isEmpty else {
                        store.toast("Udklipsholderen er tom. Kopiér backuppen først.")
                        return
                    }
                    readBackup(Data(s.utf8))
                }
                .buttonStyle(BlockButtonStyle(outline: true, small: true))
            }
            HStack(spacing: 10) {
                Button("Del som fil") { exportFile() }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
                Button("Hent fra fil") { showFileImporter = true }
                    .buttonStyle(BlockButtonStyle(outline: true, small: true))
            }
            .disabled(busy)
            Button("Slet alt") { confirmWipe = true }
                .buttonStyle(TextLinkStyle(color: T.red))
        }
        .disabled(busy || !store.isLoaded)
        .opacity(busy ? 0.6 : 1)
    }

    /// Kører tung backup-kode uden at fryse skærmen.
    private func run(_ work: @escaping @MainActor () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }

    private func refreshFields() {
        incU = fmtInput(store.settings.incU)
        incL = fmtInput(store.settings.incL)
        buddyName = store.settings.buddyName
    }

    private func restore(_ b: BackupData, keepBuddy: Bool) {
        store.applyBackup(b, keepBuddy: keepBuddy)
        refreshFields()
        pendingImport = nil
    }

    private func readBackup(_ data: Data) {
        run {
            let parsed = await Task.detached(priority: .userInitiated) { try? Backup.parse(data) }.value
            if let parsed {
                pendingImport = parsed
            } else {
                store.toast("Kunne ikke læse denne backup. Tjek at du har indsat det hele.")
            }
        }
    }

    private func importSummary(_ b: BackupData) -> String {
        let custom = b.customEx.isEmpty ? "" : " og \(b.customEx.count) egne øvelser"
        var text = "Louis: \(b.louis.log.count) træninger, \(b.louis.ex.count) øvelser med vægte\(custom)."
        if let buddy = b.buddy {
            text += " \(buddy.name): \(buddy.log.count) træninger, \(buddy.ex.count) øvelser med vægte."
            text += " Alle nuværende data bliver overskrevet."
        } else {
            text += " Det er en backup fra før makker, så den erstatter Louis' data. Vælg, om \(store.name(of: .buddy))s data skal beholdes."
        }
        return text
    }

    private func exportFile() {
        run {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            let name = "traeningsregistrering-backup-\(f.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            let data = await store.exportData()
            do {
                try data.write(to: url, options: .atomic)
                shareFile = ShareFile(url: url)
            } catch {
                store.toast("Kunne ikke lave backupfilen.")
            }
        }
    }
}

struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Delingsarket.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// .iconbtn
struct IconButton: View {
    let symbol: String
    let label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 15))
                .foregroundStyle(T.muted)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.25 : 1)
        .accessibilityLabel(label)
    }
}
