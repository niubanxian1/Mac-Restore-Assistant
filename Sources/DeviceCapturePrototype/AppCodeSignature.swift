import Foundation
import Security

enum AppCodeSignature {
    /// Production reads the current signed image. Tests inject a value.
    static var testOverrideCDHash: String?

    static func currentCDHash() -> String? {
        if let testOverrideCDHash { return testOverrideCDHash }
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let err = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard err == errSecSuccess, let info = info as? [String: Any] else { return nil }
        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return unique.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }
}
