import Nat64 "mo:base/Nat64";

module {
  public type OgyMetrics = {
        total_vesting : Nat64;
        total_locked_but_not_staked : Nat64;
        total_staked : Nat64;
        };

  public func get(total : Nat) : async Nat {
    let can = actor("a3lu7-uiaaa-aaaaj-aadnq-cai") : actor {
      get_metrics : shared query () -> async OgyMetrics;
    };
    let m = await can.get_metrics();
    return total - Nat64.toNat(m.total_vesting) - Nat64.toNat(m.total_locked_but_not_staked) - Nat64.toNat(m.total_staked);
  }

}