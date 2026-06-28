import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Entry & Provider
// ─────────────────────────────────────────────────────────────────────────────

struct WidgetEntry: TimelineEntry {
    let date: Date
    let lastPrompt: String
}

struct Provider: TimelineProvider {
    private let appGroupID = "group.com.pintsize.ai"

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, lastPrompt: "Ask PintSizeAi…")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: .now, lastPrompt: lastPrompt))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: .now, lastPrompt: lastPrompt)
        // Refresh every 15 min so last prompt stays current
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var lastPrompt: String {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return "Ask PintSizeAi…"
        }
        let url = container.appendingPathComponent("last_prompt.txt")
        return (try? String(contentsOf: url))?.trimmingCharacters(in: .whitespacesAndNewlines)
               ?? "Ask PintSizeAi…"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Views
// ─────────────────────────────────────────────────────────────────────────────

struct PintSizeWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Link(destination: URL(string: "pintsize-ai://new-chat")!) {
            ZStack {
                Color(red: 0.04, green: 0.06, blue: 0.10) // navy
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.13, green: 0.76, blue: 0.37))
                        Text("PintSizeAi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    if family != .systemSmall {
                        Text(entry.lastPrompt)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Label("New chat", systemImage: "plus.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.13, green: 0.76, blue: 0.37))
                    }
                }
                .padding(12)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget declaration
// ─────────────────────────────────────────────────────────────────────────────

struct PintSizeWidget: Widget {
    let kind = "PintSizeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PintSizeWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("PintSizeAi")
        .description("Quick access to your local AI assistant.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PintSizeWidgetBundle: WidgetBundle {
    var body: some Widget {
        PintSizeWidget()
    }
}
