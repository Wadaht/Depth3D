import SwiftUI

struct ScanTipsView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [Tip] = [
        Tip(icon: "tortoise.fill", color: .green,
            title: "Move slowly",
            body: "Sweep your phone slowly across the scene. Fast motion creates gaps and motion blur in the captured colors."),
        Tip(icon: "sun.max.fill", color: .orange,
            title: "Use even lighting",
            body: "Bright, diffuse light gives the most accurate colors. Avoid harsh shadows and direct sunlight when possible."),
        Tip(icon: "arrow.triangle.2.circlepath", color: .blue,
            title: "Walk all the way around",
            body: "Surfaces only get captured from angles you've pointed your phone at. Walk a full circle around your subject."),
        Tip(icon: "ruler.fill", color: .purple,
            title: "Stay 0.5 to 5 meters away",
            body: "LiDAR works best at this range. Closer than 0.5 m may miss detail; farther than ~5 m loses precision."),
        Tip(icon: "exclamationmark.triangle.fill", color: .yellow,
            title: "Avoid shiny or transparent surfaces",
            body: "Mirrors, glass, and very glossy materials reflect or pass through laser light and produce noisy mesh data."),
        Tip(icon: "rectangle.dashed", color: .pink,
            title: "Watch for missing patches",
            body: "If the wireframe has holes, point your camera there. Coverage builds up over time — be patient.")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(tips) { tip in
                    TipRow(tip: tip)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Scanning Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct Tip: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let body: String
}

private struct TipRow: View {
    let tip: Tip

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.icon)
                .font(.title2)
                .foregroundStyle(tip.color)
                .frame(width: 36, height: 36)
                .background(tip.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.headline)
                Text(tip.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
