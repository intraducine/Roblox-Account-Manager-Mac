#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <string.h>
#include <xpc/xpc.h>

#define APP_ID "com.intraducine.RobloxAccountManager"
#define CLIENT_REQUIREMENT "identifier \"" APP_ID "\" and certificate leaf = H\"" RAM_CERTIFICATE_SHA1 "\" and info[RAMKeychainAccessVersion] = \"1\""

static bool allowed_item(const char *service, const char *account) {
    if (!service || !account) return false;
    if (strcmp(service, APP_ID ".profile-notes") == 0)
        return strcmp(account, "notes-v1") == 0;
    if (strcmp(service, APP_ID ".session") != 0) return false;
    if (strcmp(account, "sessions-v2") == 0 || strcmp(account, "sessions-v1") == 0)
        return true;
    if (strlen(account) != 36) return false;
    for (size_t i = 0; i < 36; ++i) {
        const char *allowed = (i == 8 || i == 13 || i == 18 || i == 23)
            ? "-" : "0123456789ABCDEF";
        if (!strchr(allowed, account[i])) return false;
    }
    return true;
}

static void handle_request(xpc_object_t message, xpc_object_t reply) {
    const char *service = xpc_dictionary_get_string(message, "service");
    const char *account = xpc_dictionary_get_string(message, "account");
    const char *operation = xpc_dictionary_get_string(message, "operation");
    OSStatus status = errSecParam;
    if (!operation || !allowed_item(service, account)) {
        xpc_dictionary_set_int64(reply, "status", status);
        return;
    }

    CFStringRef serviceValue = CFStringCreateWithCString(NULL, service, kCFStringEncodingASCII);
    CFStringRef accountValue = CFStringCreateWithCString(NULL, account, kCFStringEncodingASCII);
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, serviceValue);
    CFDictionarySetValue(query, kSecAttrAccount, accountValue);
    CFRelease(serviceValue);
    CFRelease(accountValue);

#ifdef RAM_KEYCHAIN_FIXTURE
    const char *path = xpc_dictionary_get_string(message, "fixture");
    SecKeychainRef fixture = NULL;
    if (!path || SecKeychainOpen(path, &fixture) != errSecSuccess) {
        CFRelease(query);
        xpc_dictionary_set_int64(reply, "status", errSecNoSuchKeychain);
        return;
    }
    status = SecKeychainSetUserInteractionAllowed(false);
    if (status == errSecSuccess) {
        const char password[] = "disposable-ramac-keychain-fixture";
        status = SecKeychainUnlock(fixture, sizeof(password) - 1, password, true);
    }
    if (status != errSecSuccess) {
        CFRelease(fixture);
        CFRelease(query);
        xpc_dictionary_set_int64(reply, "status", status);
        return;
    }
    const void *keychains[] = { fixture };
    CFArrayRef searchList = CFArrayCreate(NULL, keychains, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(query, kSecMatchSearchList, searchList);
    CFRelease(searchList);
#endif

    if (strcmp(operation, "read") == 0) {
        CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
        CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);
        CFTypeRef result = NULL;
        status = SecItemCopyMatching(query, &result);
        if (status == errSecSuccess) {
            if (result && CFGetTypeID(result) == CFDataGetTypeID()) {
                CFDataRef data = (CFDataRef)result;
                xpc_dictionary_set_data(reply, "data", CFDataGetBytePtr(data), CFDataGetLength(data));
            } else {
                status = errSecDecode;
            }
        }
        if (result) CFRelease(result);
    } else if (strcmp(operation, "write") == 0) {
        size_t length = 0;
        const void *bytes = xpc_dictionary_get_data(message, "data", &length);
        if (bytes && length > 0) {
            CFDataRef data = CFDataCreate(NULL, bytes, length);
#ifdef RAM_KEYCHAIN_FIXTURE
            SecKeychainItemRef item = NULL;
            status = SecKeychainFindGenericPassword(
                fixture, (UInt32)strlen(service), service, (UInt32)strlen(account), account,
                NULL, NULL, &item
            );
            if (status == errSecSuccess) {
                status = SecKeychainItemModifyAttributesAndData(item, NULL, (UInt32)length, bytes);
                CFRelease(item);
            }
#else
            const void *keys[] = { kSecValueData };
            const void *values[] = { data };
            CFDictionaryRef attributes = CFDictionaryCreate(
                NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
            );
            status = SecItemUpdate(query, attributes);
            CFRelease(attributes);
#endif
            if (status == errSecItemNotFound) {
                CFDictionarySetValue(query, kSecValueData, data);
#ifdef RAM_KEYCHAIN_FIXTURE
                CFDictionaryRemoveValue(query, kSecMatchSearchList);
                CFDictionarySetValue(query, kSecUseKeychain, fixture);
#endif
                status = SecItemAdd(query, NULL);
            }
            CFRelease(data);
        }
    } else if (strcmp(operation, "delete") == 0) {
#ifdef RAM_KEYCHAIN_FIXTURE
        SecKeychainItemRef item = NULL;
        status = SecKeychainFindGenericPassword(
            fixture, (UInt32)strlen(service), service, (UInt32)strlen(account), account,
            NULL, NULL, &item
        );
        if (status == errSecSuccess) {
            status = SecKeychainItemDelete(item);
            CFRelease(item);
        }
#else
        status = SecItemDelete(query);
#endif
    }
#ifdef RAM_KEYCHAIN_FIXTURE
    CFRelease(fixture);
#endif
    CFRelease(query);
    xpc_dictionary_set_int64(reply, "status", status);
}

static void connect_peer(xpc_connection_t connection) {
    if (xpc_connection_set_peer_code_signing_requirement(connection, CLIENT_REQUIREMENT) != 0) {
        xpc_connection_cancel(connection);
        return;
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t message) {
        if (xpc_get_type(message) != XPC_TYPE_DICTIONARY) return;
        xpc_object_t reply = xpc_dictionary_create_reply(message);
        if (!reply) return;
        handle_request(message, reply);
        xpc_connection_send_message(connection, reply);
        xpc_release(reply);
    });
    xpc_connection_resume(connection);
}

int main(void) {
    xpc_main(connect_peer);
}
