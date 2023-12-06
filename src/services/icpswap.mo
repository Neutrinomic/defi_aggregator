// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type NatResult = { #ok : Nat; #err : Text };
  public type PoolInfo = {
    fee : Int;
    token0Id : Text;
    token1Id : Text;
    pool : Text;
    token1Price : Float;
    token1Standard : Text;
    token1Decimals : Float;
    token0Standard : Text;
    token0Symbol : Text;
    token0Decimals : Float;
    token0Price : Float;
    token1Symbol : Text;
  };
  public type TransactionType = {
    #decreaseLiquidity;
    #claim;
    #swap;
    #addLiquidity;
    #increaseLiquidity;
  };
  public type TransactionsType = {
    to : Text;
    action : TransactionType;
    token0Id : Text;
    token1Id : Text;
    liquidityTotal : Nat;
    from : Text;
    exchangePrice : Float;
    hash : Text;
    tick : Int;
    token1Price : Float;
    recipient : Text;
    token0ChangeAmount : Float;
    sender : Text;
    exchangeRate : Float;
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
  public type TvlChartDayData = { id : Int; tvlUSD : Float; timestamp : Int };
  public type TvlOverview = { tvlUSD : Float; tvlUSDChange : Float };
  public type Self = actor {
    cycleAvailable : shared () -> async NatResult;
    cycleBalance : shared query () -> async NatResult;
    getAllPoolTvl : shared query () -> async [(Text, Float)];
    getAllTokenTvl : shared query () -> async [(Text, Float)];
    getPoolChartTvl : shared query (Text, Nat, Nat) -> async [TvlChartDayData];
    getPoolLastTvl : shared query Text -> async TvlOverview;
    getPools : shared query () -> async [(Text, PoolInfo)];
    getSyncError : shared query () -> async Text;
    getTokenChartTvl : shared query (Text, Nat, Nat) -> async [TvlChartDayData];
    getTokenLastTvl : shared query Text -> async TvlOverview;
    saveTransactions : shared TransactionsType -> async ();
  }
}