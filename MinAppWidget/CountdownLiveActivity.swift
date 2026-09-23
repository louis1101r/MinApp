import ActivityKit
import SwiftUI
import WidgetKit

struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownAttributes.self) { context in
            // Låseskærm / notifikationsbanner
            HStack {
                Image(systemName: "timer")
                Text(context.attributes.title)
                Spacer()
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .font(.title2.bold())
                    .multilineTextAlignment(.trailing)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                        .monospacedDigit()
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}
