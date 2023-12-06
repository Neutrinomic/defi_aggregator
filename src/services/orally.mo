
module {
  public type BalancesCfg = {
    rpc : Text;
    erc20_contract : Nat;
    fee_per_byte : Nat;
    chain_id : Nat;
  };
  public type BoolResponse = { #Ok : Bool; #Err : Text };
  public type Cfg = {
    mock : Bool;
    exchange_rate_canister : Text;
    balances_cfg : BalancesCfg;
    key_name : Text;
  };
  public type CreateCustomPairRequest = {
    msg : Text;
    sig : Text;
    decimals : Nat;
    update_freq : Nat;
    sources : [Source];
    pair_id : Text;
  };
  public type CreateDataFetcherRequest = {
    msg : Text;
    sig : Text;
    update_freq : Nat;
    sources : [Source];
  };
  public type CreateDefaultPairRequest = {
    decimals : Nat;
    update_freq : Nat;
    pair_id : Text;
  };
  public type DataFetcher = {
    id : Nat;
    owner : Text;
    update_freq : Nat;
    sources : [Source];
  };
  public type Error = { #Ok; #Err : Text };
  public type GetAssetDataResponse = { #Ok : RateDataLight; #Err : Text };
  public type GetAssetDataWithProofResponse = {
    #Ok : RateDataLight;
    #Err : Text;
  };
  public type GetCfgResponse = { #Ok : Cfg; #Err : Text };
  public type GetWhitelistResponse = { #Ok : [Text]; #Err : Text };
  public type NatResponse = { #Ok : Nat; #Err : Text };
  public type Pair = {
    id : Text;
    status : PairStatus;
    decimals : Nat64;
    owner : Text;
    data : ?RateDataLight;
    update_freq : Nat64;
    pair_type : PairType;
  };
  public type PairStatus = {
    requests_counter : Nat64;
    updated_counter : Nat64;
    last_update : Nat64;
  };
  public type PairType = { #Default; #Custom : { sources : [Source] } };
  public type RateDataLight = {
    decimals : Nat64;
    signature : ?Text;
    rate : Nat64;
    timestamp : Nat64;
    symbol : Text;
  };
  public type Source = { uri : Text; resolver : Text; expected_bytes : Nat64 };
  public type TextResponse = { #Ok : Text; #Err : Text };
  public type UpdateCfg = {
    mock : ?Bool;
    exchange_rate_canister : ?Text;
    balances_cfg : ?BalancesCfg;
    key_name : ?Text;
  };
  public type Self = actor {
    add_to_whitelist : shared Text -> async Error;
    clear_state : shared () -> async Error;
    create_custom_pair : shared CreateCustomPairRequest -> async Error;
    create_data_fetcher : shared CreateDataFetcherRequest -> async NatResponse;
    create_default_pair : shared CreateDefaultPairRequest -> async Error;
    deposit : shared (Text, Text, Text) -> async Error;
    eth_address : shared () -> async TextResponse;
    get_asset_data : shared Text -> async GetAssetDataResponse;
    get_asset_data_with_proof : shared Text -> async GetAssetDataWithProofResponse;
    get_balance : shared Text -> async NatResponse;
    get_cfg : shared () -> async GetCfgResponse;
    get_data : shared Nat -> async TextResponse;
    get_data_fetchers : shared Text -> async [DataFetcher];
    get_pairs : shared () -> async [Pair];
    get_whitelist : shared () -> async GetWhitelistResponse;
    is_pair_exists : shared Text -> async Bool;
    is_whitelisted : shared Text -> async BoolResponse;
    remove_custom_pair : shared (Text, Text, Text) -> async Error;
    remove_data_fetcher : shared (Nat, Text, Text) -> async Error;
    remove_default_pair : shared Text -> async Error;
    remove_from_whitelist : shared Text -> async Error;
    update_cfg : shared UpdateCfg -> async Error;
    withdraw : shared (Nat, Text, Text, Text) -> async TextResponse;
    withdraw_fees : shared Text -> async TextResponse;
  }
}