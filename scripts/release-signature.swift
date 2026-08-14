import CryptoKit
import Foundation
import LocalAuthentication
import Security

private let accessPrompt = "Approve this Roblox Account Manager release signature."

private enum ReleaseSignatureError: LocalizedError {
    case invalidArguments
    case accessControl(String)
    case invalidKey
    case missingKey
    case secureEnclaveUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Use create, public-key, sign <archive> <signature>, or verify <archive> <signature>."
        case .accessControl(let message):
            return "The Secure Enclave could not create the required user-presence control: \(message)"
        case .invalidKey:
            return "The stored Secure Enclave release-signing key is invalid."
        case .missingKey:
            return "The release-signing key is missing. Run this script with create first."
        case .secureEnclaveUnavailable:
            return "This Mac does not provide the Secure Enclave required for release signing."
        }
    }
}

private func signingKeyURL() throws -> URL {
    guard let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first else {
        throw ReleaseSignatureError.invalidKey
    }
    return applicationSupport
        .appendingPathComponent("Roblox Account Manager", isDirectory: true)
        .appendingPathComponent("Release Signing", isDirectory: true)
        .appendingPathComponent("p256-secure-enclave-v2.key", isDirectory: false)
}

private func authenticationContext() -> LAContext {
    let context = LAContext()
    context.localizedReason = accessPrompt
    return context
}

private func userPresenceAccessControl() throws -> SecAccessControl {
    var error: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        [.privateKeyUsage, .userPresence],
        &error
    ) else {
        let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
        throw ReleaseSignatureError.accessControl(message)
    }
    return accessControl
}

private func loadPrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey? {
    guard SecureEnclave.isAvailable else {
        throw ReleaseSignatureError.secureEnclaveUnavailable
    }
    let keyURL = try signingKeyURL()
    guard FileManager.default.fileExists(atPath: keyURL.path) else { return nil }
    do {
        let representation = try Data(contentsOf: keyURL)
        return try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: representation,
            authenticationContext: authenticationContext()
        )
    } catch {
        throw ReleaseSignatureError.invalidKey
    }
}

private func createPrivateKeyIfNeeded() throws -> SecureEnclave.P256.Signing.PrivateKey {
    if let existing = try loadPrivateKey() { return existing }
    guard SecureEnclave.isAvailable else {
        throw ReleaseSignatureError.secureEnclaveUnavailable
    }
    let key = try SecureEnclave.P256.Signing.PrivateKey(
        accessControl: userPresenceAccessControl(),
        authenticationContext: authenticationContext()
    )
    let keyURL = try signingKeyURL()
    let directoryURL = keyURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try key.dataRepresentation.write(to: keyURL, options: [.atomic])
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: keyURL.path
    )
    return key
}

private func requirePrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    guard let key = try loadPrivateKey() else { throw ReleaseSignatureError.missingKey }
    return key
}

private func printPublicKey(_ key: SecureEnclave.P256.Signing.PrivateKey) {
    print(key.publicKey.x963Representation.base64EncodedString())
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw ReleaseSignatureError.invalidArguments }
    switch command {
    case "create" where arguments.count == 1:
        printPublicKey(try createPrivateKeyIfNeeded())
    case "public-key" where arguments.count == 1:
        printPublicKey(try requirePrivateKey())
    case "sign" where arguments.count == 3:
        let archiveURL = URL(fileURLWithPath: arguments[1])
        let signatureURL = URL(fileURLWithPath: arguments[2])
        let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let signature = try requirePrivateKey().signature(for: archive).derRepresentation
        try signature.write(to: signatureURL, options: .atomic)
        print("Signed: \(signatureURL.path)")
    case "verify" where arguments.count == 3:
        let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
        let signatureData = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard try requirePrivateKey().publicKey.isValidSignature(signature, for: archive) else {
            throw ReleaseSignatureError.invalidKey
        }
        print("Release signature is valid.")
    default:
        throw ReleaseSignatureError.invalidArguments
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
