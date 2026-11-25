import SwiftUI

struct LifetimeSheet<Content: View, Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    let width: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            content

            Divider()
            HStack(spacing: 8) {
                Spacer()
                actions
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: width)
    }
}
