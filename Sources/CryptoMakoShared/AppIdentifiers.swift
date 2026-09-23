import Foundation

public enum AppIdentifiers {
    public static let hostBundleID = "net.gschimmel.cryptomako.ios"
    public static let extensionBundleID = "net.gschimmel.cryptomako.ios.FileProvider"
    public static let shareExtensionBundleID = "net.gschimmel.cryptomako.ios.Share"

    /// iOS App Groups use the bare `group.` form (matches entitlements).
    /// macOS sibling uses a team-prefixed group on a different bundle — not shared.
    public static let appGroup = "group.net.gschimmel.cryptomako.ios"

    /// Keychain service name.
    public static let keychainService = "net.gschimmel.cryptomako.ios"
    /// Must match `keychain-access-groups` with Team ID prefix.
    public static let keychainAccessGroup = "H4K6YW7MQM.group.net.gschimmel.cryptomako.ios"

    public static let secretKeyAccount = "s3-secret-key"
    public static let passwordAccount = "vault-password"
    public static let proxyPasswordAccount = "http-proxy-password"

    /// Domain identifier is derived from the vault JWT `jti` so two vaults never collide.
    public static func domainIdentifier(jti: String) -> String {
        "cryptomako.ios.\(jti)"
    }

    /// App-group relative folder where the Share extension drops inbound files.
    public static let shareInboxFolderName = "ShareInbox"
}
