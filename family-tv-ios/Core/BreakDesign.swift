import Foundation

enum BreakDesign {
    /// Product defaults for predictability, not a clinical threshold or a safety guarantee.
    static let shortIntervalNotice = 15 * 60
    static func hasShortIntervals(_ policy: ViewingPolicy) -> Bool {
        [policy.initial_seconds, policy.first_reward_seconds, policy.second_reward_seconds, policy.repeat_seconds].contains { $0 < shortIntervalNotice }
    }
    static func steadyIntervals(_ policy: ViewingPolicy) -> ViewingPolicy {
        var copy = policy
        copy.initial_seconds = max(policy.initial_seconds, 20 * 60)
        copy.first_reward_seconds = 20 * 60
        copy.second_reward_seconds = 20 * 60
        copy.repeat_seconds = 20 * 60
        return copy
    }
}
