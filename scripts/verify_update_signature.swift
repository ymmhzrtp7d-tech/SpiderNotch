// Checks that an update archive's EdDSA (ed25519) signature matches the PUBLIC
// key built into the app, exactly as Sparkle will check it on people's Macs.
// Usage: swift scripts/verify_update_signature.swift FILE SIGNATURE_BASE64 PUBLIC_KEY_BASE64
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let data = FileManager.default.contents(atPath: args[1]),
      let signature = Data(base64Encoded: args[2]),
      let keyData = Data(base64Encoded: args[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write("Usage: verify_update_signature.swift FILE SIGNATURE PUBLIC_KEY\n".data(using: .utf8)!)
    exit(2)
}
if key.isValidSignature(signature, for: data) {
    print("Update signature matches the app's public key.")
    exit(0)
}
FileHandle.standardError.write("Update signature does NOT match the app's public key.\n".data(using: .utf8)!)
exit(1)
