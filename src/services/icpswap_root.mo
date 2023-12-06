// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type Address = Text;
  public type NatResult = { #ok : Nat; #err : Text };
  public type PublicPoolOverView = {
    id : Nat;
    token0TotalVolume : Float;
    volumeUSD1d : Float;
    volumeUSD7d : Float;
    token0Id : Text;
    token1Id : Text;
    totalVolumeUSD : Float;
    sqrtPrice : Float;
    pool : Text;
    tick : Int;
    liquidity : Nat;
    token1Price : Float;
    feeTier : Nat;
    token1TotalVolume : Float;
    volumeUSD : Float;
    feesUSD : Float;
    token1Standard : Text;
    txCount : Nat;
    token1Decimals : Float;
    token0Standard : Text;
    token0Symbol : Text;
    token0Decimals : Float;
    token0Price : Float;
    token1Symbol : Text;
  };
  public type PublicTokenOverview = {
    id : Nat;
    volumeUSD1d : Float;
    volumeUSD7d : Float;
    totalVolumeUSD : Float;
    name : Text;
    volumeUSD : Float;
    feesUSD : Float;
    priceUSDChange : Float;
    address : Text;
    txCount : Int;
    priceUSD : Float;
    standard : Text;
    symbol : Text;
  };
  public type Transaction = {
    to : Text;
    action : TransactionType;
    token0Id : Text;
    token1Id : Text;
    liquidityTotal : Nat;
    from : Text;
    hash : Text;
    tick : Int;
    token1Price : Float;
    recipient : Text;
    token0ChangeAmount : Float;
    sender : Text;
    liquidityChange : Nat;
    token1Standard : Text;
    token0Fee : Float;
    token1Fee : Float;
    timestamp : Int;
    token1ChangeAmount : Float;
    token1Decimals : Float;
    token0Standard : Text;
    amountUSD : Float;
    amountToken0 : Float;
    amountToken1 : Float;
    poolFee : Nat;
    token0Symbol : Text;
    token0Decimals : Float;
    token0Price : Float;
    token1Symbol : Text;
    poolId : Text;
  };
  public type TransactionType = {
    #decreaseLiquidity;
    #claim;
    #swap;
    #addLiquidity;
    #increaseLiquidity;
  };
  public type Self = actor {
    addOwner : shared Principal -> async ();
    allPoolStorage : shared query () -> async [Text];
    allTokenStorage : shared query () -> async [Text];
    allUserStorage : shared query () -> async [Text];
    batchInsert : shared [Transaction] -> async ();
    clean : shared () -> async ();
    cycleAvailable : shared () -> async NatResult;
    cycleBalance : shared query () -> async NatResult;
    getAllPools : shared query () -> async [PublicPoolOverView];
    getAllTokens : shared query () -> async [PublicTokenOverview];
    getDataQueueSize : shared query () -> async Nat;
    getLastDataTime : shared query () -> async Int;
    getOwners : shared () -> async [Principal];
    getPoolQueueSize : shared query () -> async [(Text, Nat)];
    getSyncLock : shared query () -> async Bool;
    getSyncStatus : shared query () -> async [(Text, Bool, Text)];
    getTokenQueueSize : shared query () -> async [(Text, Nat)];
    getUserQueueSize : shared query () -> async [(Text, Nat)];
    insert : shared Transaction -> async ();
    poolMapping : shared query () -> async [(Text, Text)];
    poolStorage : shared query Text -> async ?Text;
    setPoolSyncStatus : shared Bool -> async Bool;
    setTokenSyncStatus : shared Bool -> async Bool;
    setUserSyncStatus : shared Bool -> async Bool;
    syncOverview : shared () -> async ();
    tokenMapping : shared query () -> async [(Text, Text)];
    tokenStorage : shared query Text -> async ?Text;
    userMapping : shared query () -> async [(Text, Text)];
    userStorage : shared query Address -> async ?Text;
  }
}