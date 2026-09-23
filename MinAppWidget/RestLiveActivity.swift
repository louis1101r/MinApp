import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0x5C / 255, green: 0x8D / 255, blue: 0xFF / 255)

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenRestView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PAUSE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(context.attributes.workout)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, isStale: context.isStale)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(accent)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            } compactTrailing: {
                RestCountdown(state: context.state, isStale: context.isStale)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

/// Nedtælling med Text(timerInterval:). Når pausen er udløbet, står der "Nu".
struct RestCountdown: View {
    var state: RestActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        if isStale || state.endDate <= Date() {
            Text("Nu")
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: state.startDate...state.endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

struct LockScreenRestView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.isStale ? "PAUSEN ER SLUT" : "PAUSE · " + context.attributes.workout.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(context.state.title)
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)
                Text(context.state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            RestCountdown(state: context.state, isStale: context.isStale)
                .font(.system(size: 40, weight: .heavy))
                .frame(minWidth: 96, alignment: .trailing)
        }
        .padding(16)
    }
}
