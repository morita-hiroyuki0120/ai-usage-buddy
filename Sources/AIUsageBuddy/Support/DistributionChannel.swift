/// The distribution channel controls integrations that are not available in every build.
public enum DistributionChannel: Equatable, Sendable {
    case direct
    case appStore

    /// Store builds opt in explicitly; existing builds remain direct by default.
    public static var current: DistributionChannel {
        #if AI_USAGE_BUDDY_APP_STORE
        .appStore
        #else
        .direct
        #endif
    }

    public var isAppStore: Bool {
        self == .appStore
    }
}
