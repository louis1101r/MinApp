import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let accent = Color(red: 0x5C / 255, green: 0x8D / 255, blue: 0xFF / 255)

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            LockScreenRestView(context: context)
        } dynamicIsland: { context in
            let people = context.state.people
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("PAUSE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.workout)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ForEach(people, id: \.profile) { p in
                            if people.count > 1 {
                                CompactPersonRow(person: p, isStale: context.isStale, ink: .white, onInk: .black)
                            } else {
                                PersonRow(person: p, isStale: context.isStale, showName: false,
                                          ink: .white, onInk: .black, timerSize: 28)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if let first = people.first, people.count > 1 {
                    CompactTimer(person: first, isStale: context.isStale)
                } else {
                    Image(systemName: "timer")
                        .foregroundStyle(accent)
                }
            } compactTrailing: {
                if let p = people.last {
                    CompactTimer(person: p, isStale: context.isStale)
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

/// Nedtælling med Text(timerInterval:). "Nu" når pausen er slut, "–" uden pause.
struct RestCountdown: View {
    var person: RestAttributes.Person
    var isStale: Bool

    var body: some View {
        if let s = person.startDate, let e = person.endDate, !isStale, e > Date(), e > s {
            Text(timerInterval: s...e, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else if person.endDate != nil {
            Text("Nu")
                .multilineTextAlignment(.trailing)
        } else {
            Text("–")
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Kompakt Dynamic Island: forbogstav + nedtælling.
struct CompactTimer: View {
    var person: RestAttributes.Person
    var isStale: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(String(person.name.prefix(1)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            RestCountdown(person: person, isStale: isStale)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: 58)
    }
}

/// Én person: navn, seneste sæt, næste sæt, nedtælling og knapperne.
struct PersonRow: View {
    var person: RestAttributes.Person
    var isStale: Bool
    var showName: Bool
    var ink: Color
    var onInk: Color
    var timerSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(header)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(person.title)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(1)
                    Text(person.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                RestCountdown(person: person, isStale: isStale)
                    .font(.system(size: timerSize, weight: .heavy))
                    .frame(minWidth: 70, alignment: .trailing)
            }
            RestButtons(profile: person.profile, ink: ink, onInk: onInk)
        }
    }

    private var header: String {
        var parts: [String] = []
        if showName { parts.append(person.name.uppercased()) }
        if !person.last.isEmpty { parts.append("SIDST " + person.last) }
        return parts.isEmpty ? "PAUSE" : parts.joined(separator: " · ")
    }
}

/// Træn sammen: én kompakt linje per person, så to personer kan være på låseskærmen.
struct CompactPersonRow: View {
    var person: RestAttributes.Person
    var isStale: Bool
    var ink: Color
    var onInk: Color

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(person.last.isEmpty ? person.name.uppercased() : person.name.uppercased() + " · SIDST " + person.last)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(person.detail.isEmpty ? person.title : person.title + " · " + person.detail)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            RestCountdown(person: person, isStale: isStale)
                .font(.system(size: 24, weight: .heavy))
                .frame(minWidth: 62, alignment: .trailing)
            Button(intent: CompleteSetIntent(profile: person.profile)) {
                Text("✓")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 30)
                    .foregroundStyle(onInk)
                    .background(ink)
            }
            .buttonStyle(.plain)
            Button(intent: AddRestTimeIntent(profile: person.profile)) {
                Text("+15")
                    .font(.caption.weight(.bold))
                    .frame(width: 38, height: 30)
                    .foregroundStyle(ink)
                    .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Knapperne "✓ Sæt færdigt" og "+15 sek" (App Intents, kører i appen).
struct RestButtons: View {
    var profile: String
    var ink: Color
    var onInk: Color

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteSetIntent(profile: profile)) {
                Text("✓ Sæt færdigt")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(onInk)
                    .background(ink)
            }
            .buttonStyle(.plain)
            Button(intent: AddRestTimeIntent(profile: profile)) {
                Text("+15 sek")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(ink)
                    .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }
}

struct LockScreenRestView: View {
    let context: ActivityViewContext<RestAttributes>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let people = context.state.people
        let ink: Color = scheme == .dark ? .white : .black
        let onInk: Color = scheme == .dark ? .black : .white
        VStack(alignment: .leading, spacing: people.count > 1 ? 10 : 12) {
            if people.count > 1 {
                Text(context.isStale ? "PAUSEN ER SLUT" : "PAUSE · " + context.attributes.workout.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(people, id: \.profile) { p in
                if people.count > 1 {
                    CompactPersonRow(person: p, isStale: context.isStale, ink: ink, onInk: onInk)
                } else {
                    PersonRow(person: p, isStale: context.isStale, showName: false,
                              ink: ink, onInk: onInk, timerSize: 40)
                }
            }
        }
        .padding(people.count > 1 ? 14 : 16)
    }
}
