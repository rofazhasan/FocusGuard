import Foundation
import CryptoKit

public struct KeypairIdentity {
    public let privateKeyRaw: Data
    public let publicKeyRaw: Data
    public let publicKeyBase64: String
}

public final class CryptoService {
    public static func generateEd25519Keypair() -> KeypairIdentity {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let rawPub = publicKey.rawRepresentation
        let rawPriv = privateKey.rawRepresentation
        return KeypairIdentity(
            privateKeyRaw: rawPriv,
            publicKeyRaw: rawPub,
            publicKeyBase64: rawPub.base64EncodedString()
        )
    }
}
