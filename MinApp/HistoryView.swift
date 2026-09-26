import SwiftUI

/// viewHist(): samlet volumen, øvelser med 1RM-kurver og de seneste træninger, for den valgte profil.
struct HistoryView: View {
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let p = store.histProfile
        let ix = store.ix(p)
        let ids = store.byGroupOrder(store.exKeys.filter { !ix.exStats($0).isEmpty })

        VStack(alignment: .leading, spacing: 0) {
            SegmentPicker(
                items: Profile.allCases.map { ($0, store.name(of: $0)) },
                value: Binding(get: { store.histProfile }, set: { store.histProfile = $0 })
            )
            .padding(.bottom, 22)

            if !store.isLoaded {
                Text("Indlæser…")
                    .leadStyle()
            } else if ids.isEmpty {
                Text("Ingen data endnu")
                    .displayStyle()
                Text(emptyText(p))
                    .leadStyle()
                    .padding(.top, 8)
            } else {
                Text("Udvikling")
                    .displayStyle(28)
                Text("Kurverne viser den estimerede 1RM over tid. Tryk på en øvelse for den store graf.")
                    .leadStyle()
                    .padding(.top, 8)

                let last12 = Array(ix.summaries.suffix(12))
                Sec {
                    SectionTitle(text: "Samlet volumen per træning")
                    if !last12.isEmpty {
                        VolumeChart(
                            vols: last12.map(\.volume),
                            firstDate: last12.first?.date ?? "",
                            lastDate: last12.last?.date ?? ""
                        )
                    }
                }

                SectionTitle(text: "Øvelser")
                    .padding(.top, 30)
                    .padding(.bottom, 10)
                ExerciseTable(ids: ids, index: ix)
                Text("1RM er et estimat af, hvad du kunne tage én gang, regnet ud fra vægt, gentagelser og hvad du havde i tanken. Det er den kurve, der skal stige, ikke nødvendigvis vægten.")
                    .smallMuted()
                    .padding(.top, 12)

                Sec {
                    SectionTitle(text: "Træninger")
                    VStack(spacing: 0) {
                        ForEach(Array(ix.summaries.suffix(30).reversed().enumerated()), id: \.offset) { _, l in
                            LogRow(l: l)
                        }
                    }
                }
            }
        }
        .foregroundStyle(T.ink)
        .padding(.top, 22)
        .id(p)
    }

    private func emptyText(_ p: Profile) -> String {
        if p == .louis {
            return "Efter din første træning står hver øvelse her med en kurve over din udvikling."
        }
        return "Når I har trænet sammen, står " + store.name(of: p) + "s øvelser her med en kurve over udviklingen."
    }
}

/// .tbl.h4: Øvelse · Kurve · Sidst · Udvikling
struct ExerciseTable: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.present) private var present
    let ids: [String]
    let index: ProfileIndex

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Øvelse").frame(maxWidth: .infinity, alignment: .leading)
                Text("Kurve").frame(width: 64, alignment: .trailing)
                Text("Sidst").frame(width: 66, alignment: .trailing)
                Text("Udvikling").frame(width: 58, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(T.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }

            ForEach(Array(ids.enumerated()), id: \.element) { idx, id in
                row(id, idx)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 2) }
    }

    private func row(_ id: String, _ idx: Int) -> some View {
        let r = index.exStats(id)
        let last = r[r.count - 1]
        let first = r[0]
        let d: Double = r.count > 1 ? (last.e1 - first.e1) / first.e1 * 100 : 0
        let ds: String = r.count > 1 ? percentText(d) : "ny"
        let color = d > 0.5 ? T.blue : (d < -0.5 ? T.red : T.muted)
        let changeColor = d > 0.5 ? T.blue : (d < -0.5 ? T.red : T.ink)
        return Button {
            present(.stats(id))
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name(id))
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.15)
                        .multilineTextAlignment(.leading)
                    Text("\(store.EX(id)?.m ?? "") · 1RM \(Int(jsRound(last.e1))) kg")
                        .font(.system(size: 11))
                        .foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(values: r.map(\.e1), color: color, delay: min(Double(idx) * 0.045, 0.6))
                    .frame(width: 64, alignment: .trailing)
                Text(fmt(last.best.w) + " × " + fmt(last.best.r))
                    .font(.system(size: 15))
                    .frame(width: 66, alignment: .trailing)
                Text(ds)
                    .font(.system(size: 15, weight: d > 0.5 || d < -0.5 ? .bold : .regular))
                    .foregroundStyle(changeColor)
                    .frame(width: 58, alignment: .trailing)
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(T.ink)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
    }
}

/// Træninger: navn · sæt · tons · dato
struct LogRow: View {
    let l: LogSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(l.name)
                .font(.system(size: 15))
            Spacer()
            Text("\(l.setCount) sæt · \(fmt(l.volume / 1000)) t · \(l.date)")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(T.muted)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
    }
}

/// openStats(id): stor graf med 1RM / tungeste sæt / volumen og en tabel.
struct StatsView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.closeSheet) private var closeSheet
    let id: String
    @State private var metric: Metric = .e1

    var body: some View {
        let r = store.ix(store.histProfile).exStats(id)
        let who = store.histProfile == .louis ? "" : " · " + store.name(of: store.histProfile)
        InfoSheet(title: store.name(id) + who, close: { closeSheet() }) {
            NavigationLink(value: SheetPush.info(id)) {
                Text("ⓘ Om øvelsen")
            }
            .buttonStyle(TextLinkStyle())

            if let last = r.last, let first = r.first {
                let d: Double = r.count > 1 ? (last.e1 - first.e1) / first.e1 * 100 : 0
                Text("Estimeret 1RM nu")
                    .leadStyle()
                    .padding(.top, 10)
                Text("\(Int(jsRound(last.e1))) kg")
                    .font(.system(size: 46, weight: .heavy))
                    .tracking(-1.6)
                    .monospacedDigit()
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                Text(changeText(d, count: r.count, firstE1: first.e1))
                    .smallMuted()

                MetricPicker(value: $metric)
                    .padding(.top, 18)
                StatChart(rows: r, key: metric)
                Text(metric.note)
                    .smallMuted()

                StatTable(rows: r)
                    .padding(.top, 16)
            }

            Button("Luk") { closeSheet() }
                .buttonStyle(BlockButtonStyle(outline: true))
                .padding(.top, 22)
        }
    }

    private func changeText(_ d: Double, count: Int, firstE1: Double) -> String {
        if count <= 1 { return "Første logning. Kom igen." }
        let first = String(Int(jsRound(firstE1)))
        return percentText(d) + " siden første logning (" + first + " kg)"
    }
}

/// (d>0?"+":"")+Math.round(d)+" %"
func percentText(_ d: Double) -> String {
    let sign = d > 0 ? "+" : ""
    return sign + String(Int(jsRound(d))) + " %"
}

/// .pick.seg: 1RM · Tungeste sæt · Volumen
struct MetricPicker: View {
    @Binding var value: Metric

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Metric.allCases.enumerated()), id: \.element) { idx, m in
                let on = value == m
                Button {
                    value = m
                } label: {
                    Text(m.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? T.onInk : T.ink)
                        .background(on ? T.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                if idx < Metric.allCases.count - 1 {
                    Rectangle().fill(T.ink).frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(T.ink, lineWidth: 2))
    }
}

/// Tabellen i openStats: Dato · Bedste sæt · Sæt · 1RM (nyeste først).
struct StatTable: View {
    let rows: [StatRow]

    var body: some View {
        VStack(spacing: 0) {
            line(["Dato", "Bedste sæt", "Sæt", "1RM"], header: true)
            ForEach(Array(rows.reversed().enumerated()), id: \.offset) { _, x in
                line([x.date, fmt(x.best.w) + " × " + fmt(x.best.r), "\(x.sets)", "\(Int(jsRound(x.e1)))"], header: false)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(T.line).frame(height: 2) }
    }

    private func line(_ c: [String], header: Bool) -> some View {
        HStack(spacing: 6) {
            Text(c[0])
                .font(.system(size: header ? 11 : 15, weight: header ? .semibold : .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(c[1]).frame(width: 90, alignment: .trailing)
            Text(c[2]).frame(width: 44, alignment: .trailing)
            Text(c[3]).frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: header ? 11 : 15, weight: header ? .semibold : .regular))
        .foregroundStyle(header ? T.muted : T.ink)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, header ? 8 : 13)
        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
    }
}
