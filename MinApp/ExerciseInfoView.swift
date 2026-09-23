import SwiftUI

/// showExInfo(id): udgangsstilling, udførelse, fokuspunkter og typiske fejl.
struct ExerciseInfoView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    var body: some View {
        InfoSheet(title: store.name(id), close: { dismiss() }) {
            if let x = store.EX(id) {
                Text("\(x.m) · \(store.stSets(id)) × \(x.lo)–\(x.hi) · pause \(restLabel(x.r))")
                    .leadStyle()
                    .padding(.top, 8)

                if let d = Catalog.desc[id] {
                    InfoHeading(text: "Udgangsstilling")
                    InfoParagraph(text: d.s)
                    InfoHeading(text: "Udførelse")
                    InfoParagraph(text: d.u)
                    InfoHeading(text: "Fokuspunkter")
                    BulletList(items: d.f, marker: T.ink)
                    InfoHeading(text: "Typiske fejl")
                    BulletList(items: d.x, marker: T.red)
                } else if let own = x.d, !own.isEmpty {
                    InfoHeading(text: "Din beskrivelse")
                    InfoParagraph(text: own)
                } else {
                    Text("Der er ingen beskrivelse af denne øvelse.")
                        .leadStyle()
                        .padding(.top, 18)
                }
            }
            Button("Forstået") { dismiss() }
                .buttonStyle(BlockButtonStyle(outline: true))
                .padding(.top, 24)
        }
    }
}

/// showRIRInfo()
struct RIRInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InfoSheet(title: "Hvad er \"i tanken\"?", close: { dismiss() }) {
            Text("Det er, hvor mange gentagelser mere du kunne have taget, hvis du var blevet ved — også kaldet RIR (reps in reserve).")
                .leadStyle()
                .padding(.vertical, 14)
            Text("0 = du kunne ikke tage flere. 2 = du kunne sagtens tage 2 mere. Vær ærlig — det er det tal, appen bruger til at vurdere, om vægten skal op, ned eller blive.")
                .font(.system(size: 13))
            Button("Forstået") { dismiss() }
                .buttonStyle(BlockButtonStyle(outline: true))
                .padding(.top, 20)
        }
    }
}

/// Ark med sheetHead(): titel og luk-knap. Træk ned for at lukke.
struct InfoSheet<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .displayStyle(26)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Luk", action: close)
                        .buttonStyle(TextLinkStyle())
                }
                content
            }
            .foregroundStyle(T.ink)
            .frame(maxWidth: T.maxWidth, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(T.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(0)
    }
}

struct InfoHeading: View {
    let text: String
    var body: some View {
        SectionTitle(text: text)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }
}

struct InfoParagraph: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct BulletList: View {
    let items: [String]
    let marker: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(marker)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 15))
            }
        }
    }
}
