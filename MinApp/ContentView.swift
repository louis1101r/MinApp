import ActivityKit
import SwiftUI

struct ContentView: View {
    @State private var status = ""

    var body: some View {
        VStack(spacing: 20) {
            Button("Start 5 min nedtælling") {
                startCountdown()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func startCountdown() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities er slået fra i Indstillinger"
            return
        }

        let start = Date()
        let end = start.addingTimeInterval(5 * 60)
        let attributes = CountdownAttributes(title: "Nedtælling")
        let state = CountdownAttributes.ContentState(startDate: start, endDate: end)

        do {
            _ = try Activity<CountdownAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            status = "Nedtælling startet"
        } catch {
            status = "Kunne ikke starte: \(error.localizedDescription)"
        }
    }
}
