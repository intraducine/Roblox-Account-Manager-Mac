import Foundation
import Security
import XPC

struct KeychainItemAccess {
    static let sessionService = "com.intraducine.RobloxAccountManager.session"
    static let notesService = "com.intraducine.RobloxAccountManager.profile-notes"
    #if RAM_KEYCHAIN_FIXTURE
    private static let helperID = "com.intraducine.RobloxAccountManager.Keychain.Fixture"
    var fixtureKeychain: URL?
    #else
    private static let helperID = "com.intraducine.RobloxAccountManager.Keychain"
    #endif

    let service: String

    func read(_ account: String) -> (status: OSStatus, data: Data?) {
        if let reply = helperRequest("read", account: account) {
            var count = 0
            let bytes = xpc_dictionary_get_data(reply, "data", &count)
            return (OSStatus(xpc_dictionary_get_int64(reply, "status")), bytes.map { Data(bytes: $0, count: count) })
        }
        var query = itemQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func write(_ data: Data, account: String) -> OSStatus {
        if let reply = helperRequest("write", account: account, data: data) {
            return OSStatus(xpc_dictionary_get_int64(reply, "status"))
        }
        var query = itemQuery(account)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecItemNotFound else { return status }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ account: String) -> OSStatus {
        if let reply = helperRequest("delete", account: account) {
            return OSStatus(xpc_dictionary_get_int64(reply, "status"))
        }
        return SecItemDelete(itemQuery(account) as CFDictionary)
    }

    private func itemQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func helperRequest(_ operation: String, account: String, data: Data? = nil) -> xpc_object_t? {
        guard service == Self.sessionService || service == Self.notesService else { return nil }
        #if !RAM_KEYCHAIN_FIXTURE
        guard Bundle.main.object(forInfoDictionaryKey: "RAMKeychainAccessVersion") != nil else { return nil }
        #endif
        let failure = xpc_dictionary_create_empty()
        xpc_dictionary_set_int64(failure, "status", Int64(errSecNotAvailable))
        guard let fingerprint = Bundle.main.object(forInfoDictionaryKey: "RAMKeychainCertificateSHA1") as? String,
              fingerprint.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil else {
            return failure
        }
        let connection = xpc_connection_create(Self.helperID, nil)
        defer { xpc_connection_cancel(connection) }
        let requirement = "identifier \"\(Self.helperID)\" and certificate leaf = H\"\(fingerprint)\""
        guard xpc_connection_set_peer_code_signing_requirement(connection, requirement) == 0 else { return failure }
        xpc_connection_set_event_handler(connection) { _ in }
        xpc_connection_resume(connection)
        let request = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(request, "operation", operation)
        xpc_dictionary_set_string(request, "service", service)
        xpc_dictionary_set_string(request, "account", account)
        #if RAM_KEYCHAIN_FIXTURE
        guard let fixtureKeychain else { return failure }
        xpc_dictionary_set_string(request, "fixture", fixtureKeychain.path)
        #endif
        if let data {
            data.withUnsafeBytes { bytes in
                if let address = bytes.baseAddress {
                    xpc_dictionary_set_data(request, "data", address, bytes.count)
                }
            }
        }
        let reply = xpc_connection_send_message_with_reply_sync(connection, request)
        guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY,
              let rawStatus = xpc_dictionary_get_value(reply, "status"),
              xpc_get_type(rawStatus) == XPC_TYPE_INT64 else { return failure }
        return reply
    }
}
