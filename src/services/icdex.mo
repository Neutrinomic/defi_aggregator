// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  
  public type PriceResponse = { quantity : Nat; price : Nat };
  public type Amount = Nat;
  public type Vol = { value0 : Amount; value1 : Amount };

  public type Self = actor {
    level10 : shared query () -> async (
        Nat,
        { ask : [PriceResponse]; bid : [PriceResponse] },
      );
    level100 : shared query () -> async (
        Nat,
        { ask : [PriceResponse]; bid : [PriceResponse] },
      );
    stats : shared query () -> async {
        change24h : Float;
        vol24h : Vol;
        totalVol : Vol;
        price : Float;
      };
  }
}