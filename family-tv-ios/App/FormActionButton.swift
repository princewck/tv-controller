import SwiftUI

/// A submit action is visually distinct from editable rows and navigation links.
struct FormActionButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var busy = false
    var role: ButtonRole? = nil
    let action: () -> Void
    private var foreground: Color { colorScheme == .dark && role != .destructive ? .black : .white }

    private var button: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(foreground).accessibilityHidden(true) }
                Text(title).font(.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .tint(role == .destructive ? .red : .accentColor)
        .disabled(busy)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
    }
    var body: some View {
        if #available(iOS 26, *) { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.borderedProminent) }
    }
}

struct FormValidationMessage: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Color("SupportingText"))
            .fixedSize(horizontal: false, vertical: true)
    }
}
