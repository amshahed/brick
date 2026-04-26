import CryptoKit
import Foundation

enum PasscodeService {
    static func generateRandom() -> String {
        var digits = ""
        for _ in 0..<6 {
            digits.append(String(Int.random(in: 0...9)))
        }
        return digits
    }

    static func isValidUserChosen(_ code: String) -> Bool {
        (4...6).contains(code.count) && code.allSatisfy { $0.isNumber }
    }

    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ code: String, salt: String) -> String {
        let input = Data((salt + code).utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ code: String, hash expected: String, salt: String) -> Bool {
        let computed = hash(code, salt: salt)
        guard computed.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(computed.utf8, expected.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }
}
