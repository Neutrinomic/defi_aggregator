// This is a generated Motoko binding.
// Please use `import service "ic:canister_id"` instead to call canisters on the IC if possible.

module {
  public type Metadata = {
    fee : Nat;
    decimals : Nat8;
    owner : Principal;
    logo : Text;
    name : Text;
    totalSupply : Nat;
    symbol : Text;
  };
  public type Result = { #Ok : Nat; #Err : TxError };
  public type TokenInfo = {
    holderNumber : Nat64;
    deployTime : Nat64;
    metadata : Metadata;
    historySize : Nat64;
    cycles : Nat64;
    feeTo : Principal;
  };
  public type TxError = {
    #InsufficientAllowance;
    #InsufficientBalance;
    #ErrorOperationStyle;
    #Unauthorized;
    #LedgerTrap;
    #ErrorTo;
    #Other : Text;
    #BlockUsed;
    #AmountTooSmall;
  };
  public type Self = actor {
    allowance : shared query (Principal, Principal) -> async Nat;
    approve : shared (Principal, Nat) -> async Result;
    balanceOf : shared query Principal -> async Nat;
    burn : shared Nat -> async Result;
    decimals : shared query () -> async Nat8;
    getAllowanceSize : shared query () -> async Nat64;
    getHolders : shared query (Nat64, Nat64) -> async [(Principal, Nat)];
    getMetadata : shared query () -> async Metadata;
    getTokenInfo : shared query () -> async TokenInfo;
    getUserApprovals : shared query Principal -> async [(Principal, Nat)];
    historySize : shared query () -> async Nat64;
    logo : shared query () -> async Text;
    mint : shared (Principal, Nat) -> async Result;
    name : shared query () -> async Text;
    owner : shared query () -> async Principal;
    setFee : shared Nat -> async ();
    setFeeTo : shared Principal -> async ();
    setLogo : shared Text -> async ();
    setName : shared Text -> async ();
    setOwner : shared Principal -> async ();
    symbol : shared query () -> async Text;
    totalSupply : shared query () -> async Nat;
    transfer : shared (Principal, Nat) -> async Result;
    transferFrom : shared (Principal, Principal, Nat) -> async Result;
  }
}
