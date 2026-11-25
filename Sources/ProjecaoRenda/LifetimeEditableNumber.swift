import SwiftUI

struct LifetimeEditableNumber: View {
    enum Format {
        case money, titles, percent

        func display(_ value: Double) -> String {
            switch self {
            case .money: LifeStyle.money(value, cents: true)
            case .titles: LifeStyle.number(value) + " títulos"
            case .percent: LifeStyle.number(value) + "%"
            }
        }
    }

    let title: String
    let value: Double
    let format: Format
    var range: ClosedRange<Double> = 0...1_000_000_000_000
    let update: (Double) -> Void
    @State private var isEditing = false
    @State private var draft = ""
    @State private var openingValue = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextField(title, text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .onSubmit { apply() }
                .onChange(of: draft) { _, _ in invalid = false }
                .onExitCommand { cancel() }
                .onChange(of: focused) { _, focused in
                    if !focused, !apply() { cancel() }
                }
                .task {
                    focused = true
                    await Task.yield()
                    guard focused else { return }
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .help(invalid ? "Informe um valor entre \(LifeStyle.number(range.lowerBound)) e \(LifeStyle.number(range.upperBound))." : "Enter aplica. Esc cancela.")
                .accessibilityIdentifier(title + "-editor")
        } else {
            Button {
                let text = LifeStyle.number(value)
                openingValue = text
                draft = text
                isEditing = true
            } label: {
                Text(format.display(value))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Editar \(title.lowercased())")
            .accessibilityLabel("\(title), \(format.display(value))")
            .accessibilityIdentifier(title)
        }
    }

    @discardableResult
    private func apply() -> Bool {
        guard isEditing else { return true }
        if draft == openingValue {
            cancel()
            return true
        }
        let raw = draft
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.range(of: #"^-?(?:[0-9]+|[0-9]{1,3}(?:\.[0-9]{3})+)(?:,[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")),
              range.contains(value) else {
            invalid = true
            return false
        }
        cancel()
        update(value)
        return true
    }

    private func cancel() {
        isEditing = false
        invalid = false
        focused = false
    }
}
