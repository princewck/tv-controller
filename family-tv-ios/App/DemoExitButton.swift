import SwiftUI

private struct DemoExitButton: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var exiting = false

    private var button: some View {
        Button {
            guard store.demo, !exiting else { return }
            exiting = true
            dismiss()
            Task {
                guard store.demo else { return }
                await store.logout()
            }
        } label: {
            Label(L10n.tr("退出演示模式"), systemImage: "rectangle.portrait.and.arrow.right")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.vertical, 4)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        }
        .controlSize(.regular).buttonBorderShape(.capsule).frame(minHeight: 44)
        .disabled(exiting).accessibilityIdentifier("globalDemoExit")
    }

    var body: some View {
        if #available(iOS 26, *) { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.borderedProminent) }
    }
}

private struct DemoExitFloating: ViewModifier {
    @Environment(FamilyStore.self) private var store
    var bottomPadding: CGFloat
    var reservingSpace: Bool
    func body(content: Content) -> some View {
        if reservingSpace {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if store.demo {
                    HStack { Spacer(); DemoExitButton() }
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, bottomPadding)
                }
            }
        } else {
            content.overlay(alignment: .bottomTrailing) {
                if store.demo {
                    DemoExitButton().padding(.trailing, 20).padding(.bottom, bottomPadding)
                }
            }
        }
    }
}

extension View {
    func demoExitFloating(bottomPadding: CGFloat = 16, reservingSpace: Bool = false) -> some View {
        modifier(DemoExitFloating(bottomPadding: bottomPadding, reservingSpace: reservingSpace))
    }
}
