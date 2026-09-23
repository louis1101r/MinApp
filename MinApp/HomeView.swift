import SwiftUI

/// viewHome(): anbefaling, dagsform, frit valg af 1–3 muskelgrupper og sidste træning.
struct HomeView: View {
    @Environment(TrainingStore.self) private var store
    @State private var popped: String?

    var body: some View {
        let rec = store.recommend()
        let last = store.lastTrained()

        VStack(alignment: .leading, spacing: 0) {
            if store.showDeload {
                deloadBanner
                    .padding(.bottom, 18)
            }

            if rec.groups.isEmpty {
                Text("Ingen øvelser")
                    .displayStyle(30)
                Text("Tilføj øvelser til dine muskelgrupper under Program.")
                    .leadStyle()
                    .padding(.top, 8)
            } else {
                recommended(rec.groups, last: rec.last)
                readinessSection
                pickSection(last: last)
                if let l = store.log.last {
                    Sec {
                        SectionTitle(text: "Sidste træning")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(l.name)
                                .font(.system(size: 15))
                            Spacer()
                            Text(l.date + " · " + store.agoTxt(l.ts))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(T.muted)
                        }
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
                    }
                }
            }
        }
        .foregroundStyle(T.ink)
        .padding(.top, 22)
    }

    // MARK: - dele

    private var deloadBanner: some View {
        let n = store.stalled()
        return VStack(alignment: .leading, spacing: 0) {
            // Tekst med "%" sendes som String-argument, så den ikke tolkes som formatkode.
            let reason = n >= 3 ? "\(n) øvelser er gået i stå." : "Seks ugers ophobet træthed."
            let tail: String = reason + " Tag tre træninger med 30 % lavere vægt, eller sænk udgangspunktet permanent."
            let label: String = "Sænk alle vægte 10 % og nulstil"
            Text("\(Text("⚠ Kør en let uge.").bold()) \(tail)")
                .font(.system(size: 14))
            Button(label) {
                store.doDeload()
            }
            .buttonStyle(TextLinkStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(T.red, lineWidth: 2))
    }

    private func recommended(_ groups: [String], last: Double) -> some View {
        let ids = store.pickFor(groups)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Anbefalet i dag")
                .leadStyle()
                .padding(.bottom, 6)
            Text(groups.joined(separator: " + "))
                .displayStyle()
                .fixedSize(horizontal: false, vertical: true)
            Text("\(ids.count) øvelser · \(store.setsFor(ids)) sæt · \(store.restTxt(last))")
                .leadStyle()
                .monospacedDigit()
                .padding(.top, 8)
        }
    }

    private var readinessSection: some View {
        Sec {
            SectionTitle(text: "Dagsform")
            Text("Skalerer dagens vægt. Vær ærlig, ikke ambitiøs.")
                .smallMuted()
                .padding(.bottom, 2)
            ReadinessPicker(value: Binding(get: { store.readiness }, set: { store.readiness = $0 }))
            Button("Start anbefalet træning") {
                withAnimation(.easeOut(duration: 0.18)) { store.startRec() }
            }
            .buttonStyle(BlockButtonStyle())
            .padding(.top, 4)
        }
    }

    private func pickSection(last: [String: Double]) -> some View {
        Sec {
            SectionTitle(text: "Eller vælg selv")
            Text("Vælg 1–3 muskelgrupper. Under hver står, hvornår du sidst trænede den.")
                .smallMuted()
                .padding(.bottom, 2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Catalog.tg, id: \.self) { g in
                    chip(g, last: last)
                }
            }
            pickPreview
        }
    }

    private func chip(_ g: String, last: [String: Double]) -> some View {
        let n = store.groupCount(g)
        let on = store.picked.contains(g)
        return Button {
            store.togglePick(g)
            popped = g
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { popped = nil }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(g)
                    .font(.system(size: 15, weight: .bold))
                Text(n > 0 ? store.agoTxt(last[g]) : "ingen øvelser")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? T.onInk.opacity(0.65) : T.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 10)
            .foregroundStyle(on ? T.onInk : T.ink)
            .background(on ? T.ink : T.wash)
            .overlay(Rectangle().strokeBorder(on ? T.ink : T.hair, lineWidth: 1))
            .scaleEffect(popped == g ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(n == 0)
        .opacity(n == 0 ? 0.35 : 1)
    }

    @ViewBuilder
    private var pickPreview: some View {
        if !store.picked.isEmpty {
            let gs = store.sortGroups(store.picked)
            let ids = store.pickFor(gs)
            VStack(alignment: .leading, spacing: 12) {
                let title = gs.joined(separator: " + ")
                Text("\(Text(title).bold().foregroundColor(T.ink)) · \(ids.count) øvelser · \(store.setsFor(ids)) sæt")
                    .leadStyle()
                    .padding(.top, 6)
                Button("Start valgt træning") {
                    withAnimation(.easeOut(duration: 0.18)) { store.startPicked() }
                }
                .buttonStyle(BlockButtonStyle())
                if store.isFav(gs) {
                    Text("★ Gemt som favorit")
                        .smallMuted()
                } else {
                    Button("☆ Gem som favorit") { store.saveFav() }
                        .buttonStyle(TextLinkStyle())
                }
            }
            .transition(.opacity)
        }
        if !store.favs.isEmpty {
            FlowRow(spacing: 8) {
                Text("Favoritter")
                    .smallMuted()
                ForEach(Array(store.favs.enumerated()), id: \.offset) { i, f in
                    Button {
                        store.useFav(i)
                    } label: {
                        Text(f.joined(separator: " + "))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(T.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(Rectangle().strokeBorder(T.ink, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .contextMenu {
                        Button("Fjern favorit", role: .destructive) { store.removeFav(i) }
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

/// .pick: fem knapper i en sort ramme.
struct ReadinessPicker: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Catalog.readinessLabels.enumerated()), id: \.offset) { idx, item in
                let on = value == item.0
                Button {
                    value = item.0
                } label: {
                    Text(item.1)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(on ? T.onInk : T.ink)
                        .background(on ? T.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                if idx < Catalog.readinessLabels.count - 1 {
                    Rectangle().fill(T.ink).frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(T.ink, lineWidth: 2))
    }
}

/// Simpel flow-layout til favoritterne (.favs med flex-wrap).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
