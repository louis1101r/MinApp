import SwiftUI
import WidgetKit

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct SimpleProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: Date())], policy: .never))
    }
}

struct MinAppHomeWidgetView: View {
    var entry: SimpleEntry

    var body: some View {
        Text("MinApp")
            .font(.headline)
    }
}

struct MinAppHomeWidget: Widget {
    let kind = "MinAppHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleProvider()) { entry in
            MinAppHomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("MinApp")
        .description("Viser MinApp.")
        .supportedFamilies([.systemSmall])
    }
}
