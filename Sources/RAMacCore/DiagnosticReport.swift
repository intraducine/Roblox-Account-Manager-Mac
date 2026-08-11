import Darwin
import Foundation

public enum DiagnosticCheckStatus: String, Codable, Sendable {
    case passed
    case warning
    case failed
}

public struct DiagnosticCheck: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: DiagnosticCheckStatus
    public let message: String

    public init(id: String, title: String, status: DiagnosticCheckStatus, message: String) {
        self.id = id
        self.title = title
        self.status = status
        self.message = message
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let appVersion: String
    public let checks: [DiagnosticCheck]

    public init(createdAt: Date = Date(), appVersion: String = "0.5.0", checks: [DiagnosticCheck]) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.checks = checks
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public actor DiagnosticService {
    private let fileManager: FileManager
    private let accountRepository: AccountRepository
    private let vault: any SecretVault
    private let social: any RobloxSocialProviding
    private let servers: any RobloxPublicServerProviding
    private let activeLaunchRepository: ActiveLaunchTargetRepository

    public init(
        fileManager: FileManager = .default,
        accountRepository: AccountRepository,
        vault: any SecretVault,
        social: any RobloxSocialProviding = RobloxSocialAPIClient(),
        servers: any RobloxPublicServerProviding = RobloxAPIClient()
    ) {
        self.fileManager = fileManager
        self.accountRepository = accountRepository
        self.vault = vault
        self.social = social
        self.servers = servers
        self.activeLaunchRepository = ActiveLaunchTargetRepository(
            dataDirectory: accountRepository.dataDirectory,
            fileManager: fileManager
        )
    }

    public func run() async -> DiagnosticReport {
        let accounts: [ManagedAccount]
        do { accounts = try accountRepository.load() }
        catch { accounts = [] }
        var checks: [DiagnosticCheck] = []
        let robloxURL = ParallelRobloxLauncher.officialApplicationURL
        checks.append(fileManager.fileExists(atPath: robloxURL.path)
            ? DiagnosticCheck(id: "roblox-installed", title: "Roblox installation", status: .passed, message: "Roblox is installed in Applications.")
            : DiagnosticCheck(id: "roblox-installed", title: "Roblox installation", status: .failed, message: "Install Roblox in Applications."))

        if fileManager.fileExists(atPath: robloxURL.path) {
            let signatureOK = runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", robloxURL.path])
            let details = commandOutput("/usr/bin/codesign", ["-dv", "--verbose=4", robloxURL.path])
            let teamOK = details.contains("TeamIdentifier=\(ParallelRobloxLauncher.officialTeamIdentifier)")
            checks.append(DiagnosticCheck(
                id: "roblox-signature",
                title: "Roblox signature",
                status: signatureOK && teamOK ? .passed : .failed,
                message: signatureOK && teamOK
                    ? "The installed app has the expected Roblox Corporation signature."
                    : "The installed app did not pass the expected signature check."
            ))
        }

        let directory = accountRepository.dataDirectory
        let writable = fileManager.isWritableFile(atPath: directory.path)
            || fileManager.isWritableFile(atPath: directory.deletingLastPathComponent().path)
        checks.append(DiagnosticCheck(
            id: "data-directory",
            title: "Local storage",
            status: writable ? .passed : .failed,
            message: writable ? "The app can write its local data folder." : "The app cannot write its local data folder."
        ))

        let storageValues = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = storageValues?.volumeAvailableCapacityForImportantUsage ?? 0
        checks.append(DiagnosticCheck(
            id: "disk-space",
            title: "Disk space",
            status: available > 2_000_000_000 ? .passed : .warning,
            message: available > 0
                ? "About \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
                : "Available disk space could not be read."
        ))

        do {
            _ = try accountRepository.load()
            checks.append(DiagnosticCheck(id: "metadata", title: "Account data", status: .passed, message: "Account data can be read."))
        } catch {
            checks.append(DiagnosticCheck(id: "metadata", title: "Account data", status: .failed, message: "Account data could not be read."))
        }

        var missingKeychain = 0
        for account in accounts {
            if (try? vault.read(for: account.id)) == nil { missingKeychain += 1 }
        }
        checks.append(DiagnosticCheck(
            id: "keychain",
            title: "Saved sign-ins",
            status: missingKeychain == 0 ? .passed : .warning,
            message: missingKeychain == 0
                ? "Every account has a Keychain entry."
                : "\(missingKeychain) account\(missingKeychain == 1 ? " is" : "s are") signed out."
        ))

        let prepared = preparedUnmodifiedCopies(in: directory.appendingPathComponent("Instances"))
        let preparedOK = prepared.allSatisfy {
            runCommand("/usr/bin/diff", ["-rq", robloxURL.path, $0.path])
                && runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", $0.path])
        }
        checks.append(DiagnosticCheck(
            id: "prepared-copies",
            title: "Prepared Roblox copies",
            status: preparedOK ? .passed : .failed,
            message: prepared.isEmpty
                ? "No prepared unchanged copies exist yet."
                : preparedOK ? "Every prepared unchanged copy matches the installed Roblox app." : "At least one prepared copy does not match Roblox."
        ))

        do {
            let records = try activeLaunchRepository.load()
            let current = records.filter { processExists($0.processIdentifier) }
            if current.count != records.count { try activeLaunchRepository.save(current) }
            let removed = records.count - current.count
            checks.append(DiagnosticCheck(
                id: "process-records",
                title: "Managed process records",
                status: .passed,
                message: removed == 0
                    ? "No stale managed process records were found."
                    : "Removed \(removed) stale managed process record\(removed == 1 ? "" : "s")."
            ))
        } catch {
            checks.append(DiagnosticCheck(
                id: "process-records",
                title: "Managed process records",
                status: .warning,
                message: "Managed process records could not be checked."
            ))
        }

        if let first = accounts.first {
            do {
                _ = try await social.friends(of: first.userID)
                checks.append(DiagnosticCheck(id: "social", title: "Friends service", status: .passed, message: "The Roblox friends service is reachable."))
            } catch {
                checks.append(DiagnosticCheck(id: "social", title: "Friends service", status: .warning, message: error.localizedDescription))
            }
        } else {
            checks.append(DiagnosticCheck(id: "social", title: "Friends service", status: .warning, message: "Add an account before checking the friends service."))
        }

        do {
            _ = try await servers.publicServers(placeID: 1818, cursor: nil)
            checks.append(DiagnosticCheck(id: "servers", title: "Public server service", status: .passed, message: "The Roblox public server service is reachable."))
        } catch {
            checks.append(DiagnosticCheck(id: "servers", title: "Public server service", status: .warning, message: error.localizedDescription))
        }
        return DiagnosticReport(checks: checks)
    }

    private func preparedUnmodifiedCopies(in root: URL) -> [URL] {
        guard let accounts = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return accounts.map { $0.appendingPathComponent("Unmodified/Roblox.app", isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func processExists(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private func runCommand(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }

    private func commandOutput(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { return "" }
    }
}
