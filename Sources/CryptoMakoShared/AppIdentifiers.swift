import Foundation

public enum AppIdentifiers {
    public static let hostBundleID = "net.gschimmel.cryptomako.ios"
    /// Reserved for a future Files provider appex (M3).
    public static let extensionBundleID = "net.gschimmel.cryptomako.ios.FileProvider"
    /// Team-prefixed App Group. Entitlements still use $(AppIdentifierPrefix);
    /// this Swift constant must be the literal form or containerURL returns nil.
    public static let appGroup = "H4K6YW7MQM.group.net.gschimmel.cryptomako.ios"

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
}
