import SwiftUI

/// Slutskærmen efter finish(): "Programmet er justeret" med vægtene talt op fra gammel til ny.
struct FinishView: View {
    @Environment(TrainingStore.self) private var store
    let adjustments: [Adjustment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Programmet er justeret")
                .displayStyle()
                .fixedSize(horizontal: false, vertical: true)
            Text("Det her ligger klar, næste gang du rammer øvelserne.")
                .leadStyle()
                .padding(.top, 8)
                .padding(.bottom, 20)

            ForEach(adjustments) { a in
                AdjustmentRow(a: a)
            }

            Button("Færdig") {
                withAnimation(.easeOut(duration: 0.18)) { store.adjustments = nil }
            }
            .buttonStyle(BlockButtonStyle())
            .padding(.top, 24)
        }
        .foregroundStyle(T.ink)
        .padding(.top, 22)
    }
}

struct AdjustmentRow: View {
    let a: Adjustment
    @State private var shown: Double

    init(a: Adjustment) {
        self.a = a
        _shown = State(initialValue: a.from ?? a.to)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(a.n)
                    .font(.system(size: 16, weight: .semibold))
                Text(a.msg)
                    .smallMuted()
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if let from = a.from {
                    Text(fmt(from) + " → ")
                }
                CountingNumber(value: shown)
                Text(" kg")
            }
            .font(.system(size: 16, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(T.hair).frame(height: 1) }
        .onAppear {
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.6)) {
                shown = a.to
            }
        }
    }

    private var color: Color {
        guard let from = a.from else { return T.ink }
        if a.to > from { return T.blue }
        if a.to < from { return T.red }
        return T.ink
    }
}

/// animateAdjCounters(): tallet tælles op/ned under animationen.
struct CountingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(fmt(value))
    }
}
