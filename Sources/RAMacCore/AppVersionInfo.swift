import Foundation

public enum AppVersionInfo {
    public static func currentVersion(bundle: Bundle = .main) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty,
              version != "$(MARKETING_VERSION)" else {
            return "development"
        }
        return version
    }

    public static func userAgent(product: String, bundle: Bundle = .main) -> String {
        "\(product)/\(currentVersion(bundle: bundle))"
    }
}
