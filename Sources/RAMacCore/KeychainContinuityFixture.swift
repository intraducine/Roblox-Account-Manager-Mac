#if RAM_KEYCHAIN_FIXTURE
import Foundation
import Security

public enum KeychainContinuityFixture {
    public static func run(_ arguments: [String]) -> Int32? {
        guard arguments.count >= 4, arguments[1] == "--keychain-continuity-fixture" else { return nil }
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true).resolvingSymlinksInPath()
        let temp = URL(fileURLWithPath: "/private/tmp", isDirectory: true).resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent().path == temp.path,
              directory.lastPathComponent.hasPrefix("ramac-keychain-continuity."),
              FileManager.default.fileExists(atPath: directory.path) else {
            print("Invalid Keychain fixture directory")
            return 2
        }
        let keychain = directory.appendingPathComponent("Fixture.keychain-db")
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let session = KeychainVault(access: KeychainItemAccess(
            fixtureKeychain: keychain, service: KeychainItemAccess.sessionService
        ))
        let notes = KeychainProfileNoteVault(access: KeychainItemAccess(
            fixtureKeychain: keychain, service: KeychainItemAccess.notesService
        ))
        let privateLinks = ["private-server:fixture": "synthetic private server value"]
        do {
            switch arguments[3] {
            case "seed":
                let password = "disposable-ramac-keychain-fixture"
                var reference: SecKeychain?
                let status = SecKeychainCreate(keychain.path, UInt32(password.utf8.count), password, false, nil, &reference)
                guard status == errSecSuccess else { print("Fixture creation status \(status)"); return 3 }
                try session.save("first synthetic session", for: firstID)
                try session.save("second synthetic session", for: secondID)
                try session.savePrivateServerCapabilities(privateLinks)
                try notes.saveNote("synthetic note", for: firstID)
                print("Created existing Keychain entries")
            case "verify":
                guard try session.read(for: firstID) == "first synthetic session",
                      try session.read(for: secondID) == "second synthetic session",
                      try session.readPrivateServerCapabilities() == privateLinks,
                      try notes.readNote(for: firstID) == "synthetic note" else { return 4 }
                try session.save("second synthetic session", for: secondID)
                print("Read existing sign-ins, note and private links, and wrote to Keychain")
            case "install":
                guard arguments.count == 6, let version = AppVersion(arguments[5]) else { return 2 }
                let incoming = URL(fileURLWithPath: arguments[4], isDirectory: true).resolvingSymlinksInPath()
                guard incoming.path.hasPrefix(directory.path + "/"),
                      Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix(directory.path + "/") else {
                    print("Update is outside the fixture directory")
                    return 2
                }
                let placeholder = URL(string: "https://github.com/")!
                let asset = SoftwareUpdateAsset(name: "fixture", downloadURL: placeholder, byteCount: 0, digest: "")
                let release = SoftwareUpdateRelease(
                    version: version, title: "Keychain fixture", notes: "", pageURL: placeholder, publishedAt: nil,
                    archive: asset, checksum: asset, signature: asset
                )
                let installer = SoftwareUpdateInstaller(service: GitHubSoftwareUpdateService())
                _ = try installer.install(
                    PreparedSoftwareUpdate(release: release, applicationURL: incoming, workspaceURL: directory),
                    replacing: Bundle.main.bundleURL
                )
                print("Installed signed update \(version)")
            default:
                return 2
            }
            return 0
        } catch {
            print(error.localizedDescription)
            return 5
        }
    }
}
#endif
