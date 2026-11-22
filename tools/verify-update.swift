// Publishing an already signed archive only needs the public key, not Keychain access.
import Foundation
import CryptoKit

do {
    guard CommandLine.arguments.count == 4 else { throw VerificationError.invalidArguments }
    let keyText = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: keyText),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else { throw VerificationError.invalidSignature }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard key.isValidSignature(signature, for: archive) else { throw VerificationError.invalidSignature }
    print("Verified Sparkle Ed25519 archive signature using the public key.")
} catch {
    FileHandle.standardError.write(Data("Update signature verification failed: \(error)\n".utf8))
    exit(1)
}

enum VerificationError: Error { case invalidArguments, invalidSignature }
