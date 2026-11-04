import Foundation
import StoreKit
import Observation

@MainActor @Observable final class SubscriptionStore {
    static let productID = "wang.chengkai.familytv.plus.monthly"
    var product: Product?
    var entitled = false
    var expiration: Date?
    var accountTokens = Set<UUID>()
    var signedTransactions: [String] = []
    var hasPurchaseIntent = false
    var transactionHouseholds: [String: UUID] = [:]
    var transactionOriginalIDs: [String: String] = [:]
    func receipts(for household: UUID, ownedOriginalIDs: Set<String> = []) -> [String] {
        signedTransactions.filter { receipt in
            transactionHouseholds[receipt] == household || transactionOriginalIDs[receipt].map { ownedOriginalIDs.contains($0) } == true
        }
    }
    func hasAccess(for familyID: String?) -> Bool {
        guard let familyID, let token = UUID(uuidString: familyID) else { return false }
        return entitled && accountTokens.contains(token)
    }
    var loading = false
    var purchasing = false
    var message: String?
    @ObservationIgnored nonisolated(unsafe) private var updates: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var purchaseIntents: Task<Void, Never>?
    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case let .verified(transaction) = result, transaction.productID == Self.productID {
                    await self?.refreshEntitlements()

                }
            }
        }
        purchaseIntents = Task { [weak self] in
            for await intent in PurchaseIntent.intents {
                guard !Task.isCancelled else { return }
                guard intent.product.id == Self.productID else { continue }
                self?.product = intent.product
                self?.message = L10n.tr("请先确认当前登录的家庭，再继续购买订阅。")
                self?.hasPurchaseIntent = true
            }
        }
    }
    deinit { updates?.cancel(); purchaseIntents?.cancel() }
    func load() async {
        guard !loading else { return }
        message = nil
        loading = true; defer { loading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { message = L10n.tr("暂时无法获取订阅价格，请稍后重试。") }
            await refreshEntitlements()
        } catch { message = L10n.tr("无法连接 App Store，请稍后重试。") }
    }
    func refreshEntitlements() async {
        var active = false
        var latest: Date?
        var tokens = Set<UUID>()
        var receipts: [String] = []
        var households: [String: UUID] = [:]
        var originalIDs: [String: String] = [:]
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  let date = transaction.expirationDate, date > .now else { continue }
            active = true
            if let token = transaction.appAccountToken { tokens.insert(token) }
            receipts.append(result.jwsRepresentation)
            households[result.jwsRepresentation] = transaction.appAccountToken
            originalIDs[result.jwsRepresentation] = String(transaction.originalID)
            latest = max(latest ?? .distantPast, date)
        }
        if let latest = await Transaction.latest(for: Self.productID), case let .verified(transaction) = latest,
           !receipts.contains(latest.jwsRepresentation) { receipts.append(latest.jwsRepresentation); households[latest.jwsRepresentation] = transaction.appAccountToken; originalIDs[latest.jwsRepresentation] = String(transaction.originalID) }
        entitled = active; expiration = latest; accountTokens = tokens; transactionHouseholds = households; transactionOriginalIDs = originalIDs; signedTransactions = receipts
    }
    func purchase(accountToken: UUID) async {
        guard let product, !purchasing else { return }
        purchasing = true; message = nil; defer { purchasing = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
            case let .success(result):
                guard case let .verified(transaction) = result, transaction.productID == Self.productID else {
                    message = L10n.tr("购买凭证未能验证，请恢复购买或联系支持。"); return
                }
                await refreshEntitlements()

                message = entitled ? L10n.tr("Apple 已确认购买，正在同步家庭云。") : L10n.tr("订阅状态正在更新，请稍后恢复购买。")
            case .pending: message = L10n.tr("购买等待 Apple 确认，确认后会自动更新。")
            case .userCancelled: break
            @unknown default: message = L10n.tr("暂时无法完成购买，请稍后重试。")
            }
        } catch { message = L10n.tr("购买未完成，请稍后重试。") }
    }
    func finishSyncedTransactions(transactionIDs: Set<String>) async {
        for await result in Transaction.unfinished {
            if case let .verified(transaction) = result, transaction.productID == Self.productID,
               transactionIDs.contains(String(transaction.id)) { await transaction.finish() }
        }
    }
    func restore() async -> String? {
        guard !purchasing else { return nil }
        purchasing = true; defer { purchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            guard entitled else { message = L10n.tr("当前 Apple 账号没有有效订阅。"); return nil }
            let proof = try await AppTransaction.refresh()
            guard case .verified = proof else { message = L10n.tr("Apple 账号凭证未通过验证，请稍后重试。"); return nil }
            message = L10n.tr("Apple 购买已恢复，正在同步家庭云。")
            return proof.jwsRepresentation
        } catch { message = L10n.tr("未能完整恢复购买，请检查网络后重试。"); return nil }
    }
}
