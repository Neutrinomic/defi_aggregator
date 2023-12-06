import Sha256 "mo:sha2/Sha256";
import Blob "mo:base/Blob";

module {

    public func treasury_address( p: Principal, nonce: Nat64 ) : [Nat8] {
        let dg = Sha256.Digest(#sha256);
        dg.writeBlob("token-distribution":Blob);

        Blob.toArray(dg.sum());

    }
}