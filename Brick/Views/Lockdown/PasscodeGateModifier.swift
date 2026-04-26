import SwiftData
import SwiftUI

private struct PasscodeGateModifier: ViewModifier {
    let title: String
    let reason: String
    @Binding var isPresented: Bool
    let onUnlocked: () -> Void

    @Environment(\.modelContext) private var context
    @State private var settings: AppSettings?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let settings {
                    PasscodeGateView(
                        title: title,
                        reason: reason,
                        settings: settings,
                        onUnlocked: onUnlocked
                    )
                } else {
                    ProgressView().onAppear(perform: load)
                }
            }
            .onAppear(perform: load)
    }

    private func load() {
        settings = try? AppSettingsStore(context: context).loadOrCreate()
    }
}

extension View {
    func passcodeGate(
        title: String,
        reason: String,
        isPresented: Binding<Bool>,
        onUnlocked: @escaping () -> Void
    ) -> some View {
        modifier(PasscodeGateModifier(
            title: title,
            reason: reason,
            isPresented: isPresented,
            onUnlocked: onUnlocked
        ))
    }
}
