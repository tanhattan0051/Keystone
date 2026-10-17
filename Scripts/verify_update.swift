#!/usr/bin/env swift
//
// verify_update.swift — check an update archive's Ed25519 signature against a
// public key. Used by Scripts/release.sh as a pre-publish safety net: it runs
// with the public key EMBEDDED in App/Updater.swift, so signing with the wrong
// private key is caught before a release ships (a wrong-key release would make
// every installed copy reject the update, bricking auto-update).
//
// Exit 0 = signature valid. Non-zero + a message on stderr otherwise.
//
// Usage:
//   swift Scripts/verify_update.swift <public-key-base64> <file> <sig-file>
// Example:
//   swift Scripts/verify_update.swift "MJ8b...=" dist/Keystone.zip dist/Keystone.zip.sig

import Foundation
import CryptoKit

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    die("usage: verify_update.swift <public-key-base64> <file> <sig-file>")
}

guard let keyData = Data(base64Encoded: args[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
    die("public key is not valid base64")
}
guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    die("public key bytes are not a valid Ed25519 key (expected 32 raw bytes, base64-encoded)")
}
guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else {
    die("cannot read file to verify: \(args[2])")
}
guard let sigText = try? String(contentsOfFile: args[3], encoding: .utf8) else {
    die("cannot read signature file: \(args[3])")
}
// sign_update.swift prints the signature with a trailing newline.
guard let sigData = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    die("signature is not valid base64")
}
guard key.isValidSignature(sigData, for: fileData) else {
    die("signature does NOT match the file under this public key")
}
print("signature OK")
