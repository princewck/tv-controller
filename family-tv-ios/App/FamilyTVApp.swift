import SwiftUI
import Observation

@main struct FamilyTVApp: App {
    @State private var store = FamilyStore()
    @State private var subscription = SubscriptionStore()
    var body: some Scene {
        WindowGroup { RootView().environment(store).environment(subscription) }
    }
}
struct RootView: View {
    @AppStorage(L10n.preferenceKey) private var appLanguage = AppLanguage.system.rawValue
    @Environment(FamilyStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscription
    @Environment(\.scenePhase) private var scenePhase
    @State private var errorPresentation = FamilyErrorPresentation()
    var body: some View {
        Group {
            if store.connected { MainTabs() } else { WelcomeView() }
        }
        .id(appLanguage)
        .environment(\.locale, L10n.locale)
        .onChange(of: appLanguage) { _, _ in
            store.error = nil; store.notice = nil
            store.relocalizeDemoLabels()
        }
        .tint(.accentColor)
        .labeledContentStyle(ReadableFieldStyle())
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.lan.suspend() }
        }
        .task(id: store.connected && scenePhase == .active) {
            guard store.connected, scenePhase == .active else { return }
            while !Task.isCancelled {
                if !store.busy { await store.refresh() }
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
            }
        }
        .task(id: store.demo ? nil : store.auth?.token) {
            guard store.auth != nil, !store.demo else { return }
            await subscription.load()
        }
        .task(id: SubscriptionSyncID(account: store.demo ? nil : store.auth?.token, enabled: store.capabilities?.paid_history == true, receipts: subscription.signedTransactions, originalIDs: store.premium.original_ids ?? [])) {
            guard !store.demo, let id = store.auth?.identity.tenant_id, let token = UUID(uuidString: id) else { return }
            let acknowledged = await store.syncSubscriptions(subscription.receipts(for: token, ownedOriginalIDs: Set(store.premium.original_ids ?? [])))
            if !Task.isCancelled { await subscription.finishSyncedTransactions(transactionIDs: acknowledged) }
        }
        .sheet(isPresented: Binding(get: { store.pendingRecoveryCode != nil }, set: { if !$0 { store.pendingRecoveryCode = nil } })) { RecoveryCodeView() }
        .sheet(isPresented: Binding(get: { store.pendingRecoveryCode == nil && store.connected && !store.demo && subscription.hasPurchaseIntent }, set: { if !$0 { subscription.hasPurchaseIntent = false } })) {
            NavigationStack { SubscriptionView().toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("完成")) { subscription.hasPurchaseIntent = false } } } }
        }
        .familyErrorAlert()
        .environment(errorPresentation)
    }
}

@MainActor @Observable final class FamilyErrorPresentation {
    var modalOwners: Set<UUID> = []
}

private struct FamilyErrorAlert: ViewModifier {
    @Environment(FamilyStore.self) private var store
    @Environment(FamilyErrorPresentation.self) private var presentation
    @State private var ownerID = UUID()
    let inModal: Bool
    func body(content: Content) -> some View {
        content
            .alert(L10n.tr("操作未完成"), isPresented: Binding(
                get: { store.error != nil && (inModal || presentation.modalOwners.isEmpty) },
                set: { if !$0 { store.error = nil } }
            )) { Button(L10n.tr("知道了")) { store.error = nil } } message: { Text(store.error ?? "") }
            .onAppear { if inModal { presentation.modalOwners.insert(ownerID) } }
            .onDisappear { if inModal { presentation.modalOwners.remove(ownerID) } }
    }
}

extension View {
    func familyErrorAlert(inModal: Bool = false) -> some View {
        modifier(FamilyErrorAlert(inModal: inModal))
    }
}
struct MainTabs: View {
    @Environment(FamilyStore.self) private var store
    var body: some View {
        TabView {
            NavigationStack { TodayView() }.tabItem { Label(L10n.tr("今天"), systemImage: "sun.max") }
            NavigationStack { RulesView() }.tabItem { Label(L10n.tr("规则"), systemImage: "slider.horizontal.3") }
            NavigationStack { HistoryView() }.tabItem { Label(L10n.tr("记录"), systemImage: "chart.bar.xaxis") }
            NavigationStack { SettingsView() }.tabItem { Label(L10n.tr("我的"), systemImage: "person.crop.circle") }
        }
    }
}
struct DemoBanner: View {
    var body: some View {
        Label(L10n.tr("演示模式 · 所有数据均为示例"), systemImage: "play.rectangle")
            .font(.subheadline).foregroundStyle(Color("SupportingText")).accessibilityIdentifier("demoBanner")
    }
}

private struct SubscriptionSyncID: Hashable { var account: String?; var enabled: Bool; var receipts: [String]; var originalIDs: [String] }

private struct ReadableFieldStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content.foregroundStyle(Color.primary)
        } label: {
            configuration.label
        }.labeledContentStyle(.automatic)
    }
}
