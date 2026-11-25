import SwiftUI

struct LifetimeMetricCards<Content: View>: View {
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14), count: count), spacing: 14) {
            content
        }
    }
}

struct LifetimeMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.64)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 116, alignment: .top)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.09)).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lifetime-metric-\(icon)")
    }
}
