// This canister uses our own implementation of reactive programming in Motoko
// This makes it possible to send requests to multiple canisters in parallel and process the results as they arrive
import {
    Subject;
    mapAsync;
    bufferTime;
    null_func;
    pipe3;

} "mo:rxmo";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Int "mo:base/Int";
import Timer "mo:base/Timer";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import ICDex "./services/icdex";
import ICPSwap "./services/icpswap";
import ICPSwapRoot "./services/icpswap_root";
import Sonic "./services/sonic";
import ICRC1 "./ledgers/icrc1";
import SNSGov "./gov/sns";
import DIP20 "./ledgers/dip20";

import { clean_std } "./std";
import BTree "mo:stableheapbtreemap/BTree";
import Nat "mo:base/Nat";
import Error "mo:base/Error";
import XRC "./services/xrc";
import Cycles "mo:base/ExperimentalCycles";
import Nat32 "mo:base/Nat32";
import Ogy "./gov/ogy";
import Vector "mo:vector";
import Swb "mo:swb";
import Time "mo:base/Time";
import SonicVol "./services/sonicvol";

// The following code is the first on-chain version of our DeFi aggregator
// and should be considered a prototype.
// Our first version was off-chain.
// The next version will be made once our DAO is deployed and will address some of the shortcomings of this version.

actor Aggregate {

    /// Initial timestamp used as a reference for calculating time-based indices
    stable var first_tick : Time.Time = (1660052760 * 1000000000);

    // Defines the structure for storing error logs with time, description, error code, and text
    type ErrorLine = (Time.Time, Text, Error.ErrorCode, Text);

    // Vector to store error logs as they occur in the system
    let errorsLog = Swb.SlidingWindowBuffer<ErrorLine>();

    // Structure for storing information about Oracle nodes including performance metrics
    type NodeInfo = {
        var good : Nat;
        var bad : Nat;
        var last : Time.Time;
        name : Text;
    };

    type NodeInfoShared = {
        principal : Principal;
        good : Nat;
        bad : Nat;
        last : Time.Time;
        name : Text;
    };

    // Stable storage for node information, using a BTree for efficient data management
    stable let nodes = BTree.init<Principal, NodeInfo>(?8);

    type TokenId = Nat;

    // Configuration structure for SNS (Service Nervous System) related tokens
    type SnsConfig = {
        root : Principal;
        governance : Principal;
        index : Principal;
        ledger : Principal;
        swap : Principal;
        treasury_subaccount : [Nat8];
        other_treasuries : [{
            token_id : TokenId;
            owner : Principal;
            subaccount : [Nat8];
        }];
    };

    // Enumerates the locking mechanisms available for tokens (none, sns, ogy)
    type TokenLocking = {
        #none;
        #sns : SnsConfig;
        #ogy;
    };

    // Configuration details for each token, including symbol, name, decimals, and ledger information
    type TokenConfig = {
        symbol : Text;
        name : Text;
        decimals : Nat;
        locking : TokenLocking;
        ledger : {
            #none;
            #icrc1 : { ledger : Principal };
            #dip20 : { ledger : Principal };
        };
        details : [TokenDetail];
        deleted : Bool;
    };

    type TokenDetail = {
        #sns_sale : { end : Time.Time; price_usd : Float; sold_tokens : Nat };
        #link : { name : Text; href : Text };
    };

    // Structure to represent locking information in a mutable format for internal processing
    type LockingVarTick = {
        treasury : Nat;
        other_treasuries : [(TokenId, Nat)];
        var total_locked : Nat;
        dissolving : [var Nat];
        not_dissolving : [var Nat];
    };

    type LockingTick = {
        treasury : Nat;
        other_treasuries : [(TokenId, Nat)];
        total_locked : Nat;
        dissolving : [Nat];
        not_dissolving : [Nat];
    };

    type TokenTickItem = {
        fee : Nat;
        circulating_supply : Nat;
        total_supply : Nat;
        locking : ?LockingTick;
    };

    type TokenTick = [var ?TokenTickItem];
    type TokenTickShared = [?TokenTickItem];

    // Token configuration store
    stable let tokens = Vector.new<TokenConfig>();

    // Token tick information store
    stable let token_ticks_1d = Vector.init<TokenTick>((Int.abs(Time.now() - first_tick)) / (1000000000 * 60 * 60 * 24) - 1, [var]);

    // Debug counter array to track certain operations or events for debugging purposes
    // var dbgCounter : [var Nat] = Array.init<Nat>(30, 0);

    let USD : TokenId = 0;
    let BTC : TokenId = 1;
    let ETH : TokenId = 2;
    let ICP : TokenId = 3;
    let XDR : TokenId = 4;

    // Pairs

    type PairId = Nat;

    type LastBid = Float;
    type LastAsk = Float;
    type High = Float;
    type Low = Float;
    type Volume24 = Float;
    type DepthBid50 = [Float];
    type DepthAsk50 = [Float];

    //Depth in array is as follows: [1% 2% 4% 8% 15% 25% 50% 100%]

    type TickItem = (High, Low, LastBid, LastAsk, Volume24, DepthBid50, DepthAsk50); // add Depth Bitmap
    type TickLast = (PairId, LastBid, LastAsk, Volume24, DepthBid50, DepthAsk50);

    type TickShared = [?TickItem];

    type Tick = [var ?TickItem];

    type PairConfig = {
        tokens : (TokenId, TokenId);

        config : {
            #icdex : {
                canister : Principal;
            };
            #icpswap : {
                canister : Principal;
            };
            #sonic : { id : Text };
            #xrc : {
                quote_asset : XRC.Asset;
                base_asset : XRC.Asset;
            };
            #oracle : { id : Text };
        };
        deleted : Bool;
    };

    stable let pair_config = Vector.new<PairConfig>();

    stable let ticks_5m = Vector.init<Tick>((Int.abs(Time.now() - first_tick)) / (1000000000 * 60 * 5), [var]);
    stable let ticks_1h = Vector.init<Tick>((Int.abs(Time.now() - first_tick)) / (1000000000 * 60 * 60), [var]);
    stable let ticks_1d = Vector.init<Tick>((Int.abs(Time.now() - first_tick)) / (1000000000 * 60 * 60 * 24), [var]);

    stable var last_update = Time.now();

    type AdminCommand = {
        #token_add : TokenConfig;
        #token_del : TokenId;
        #token_set : (TokenId, TokenConfig);
        #token_collect : TokenId;
        #pair_add : PairConfig;
        #pair_del : PairId;
        #pair_set : (PairId, PairConfig);
    };

    let adminPrincipal = Principal.fromText("gffpl-zoaxl-xkuwi-llqyr-sjxmw-tvvc7-ei3vs-vxbno-zo5c5-v57d2-2qe");

    // Commands suitable for governance proposals can contain multiple admin commands
    public shared ({ caller }) func admin(commands : [AdminCommand]) : async () {
        assert caller == adminPrincipal;
        for (cmd in commands.vals()) {
            switch (cmd) {
                case (#token_add(t)) {
                    let id = Vector.size(tokens);
                    Vector.add(tokens, t);
                    token_requests.next<system>(id);
                };
                case (#token_del(id)) {
                    let tconfig = Vector.get(tokens, id);
                    Vector.put<TokenConfig>(tokens, id, { tconfig with deleted = true });
                };
                case (#token_set(id, t)) {
                    Vector.put<TokenConfig>(tokens, id, t);
                };
                case (#token_collect(id)) {
                    token_requests.next<system>(id);
                };
                case (#pair_add(p)) {
                    // let id = Vector.size(pair_config);
                    Vector.add(pair_config, p);
                };
                case (#pair_del(id)) {
                    let { config; tokens } = Vector.get(pair_config, id);
                    Vector.put<PairConfig>(pair_config, id, { config; tokens; deleted = true });
                };
                case (#pair_set(id, p)) {
                    Vector.put<PairConfig>(pair_config, id, p);
                };
            };
        };
    };

    private func cleanup_mem() {

        // Remove 5min tick data older than 7 days
        var idx = 0;
        var max : Nat = Vector.size(ticks_5m) - 12 * 24 * 7;
        label cleanup loop {
            Vector.put<Tick>(ticks_5m, idx, [var]);
            idx += 1;
            if (idx > max) break cleanup;
        };
    };
    cleanup_mem();

    // Outputs current token and pair configuration
    public query func get_config() : async {
        tokens : [TokenConfig];
        pairs : [PairConfig];
    } {
        {
            tokens = Vector.toArray(tokens);
            pairs = Vector.toArray(pair_config);
        };
    };

    // Sets a config for easier replication when testing
    //  public shared ({ caller }) func set_config(
    //      cfg : {
    //          tokens : [TokenConfig];
    //          pairs : [PairConfig];
    //      }
    //  ) : () {
    //      assert caller == adminPrincipal;

    //      Vector.addFromIter(tokens, cfg.tokens.vals());
    //      Vector.addFromIter(pair_config, cfg.pairs.vals());
    //  };

    /// Time frames used for aggregating data: 5 minutes, 1 hour, 1 day
    type Frame = {
        #t5m;
        #t1h;
        #t1d;
    };

    type GetError = {
        #invalid_frame;
    };

    /// Utils

    // Structure for outputting token price information including depth and volume
    type TokenPriceOutput = {
        price : Float;
        buydepth2 : Float;
        buydepth8 : Float;
        buydepth50 : Float;
        volume : Float;
    };

    // Calculates the trusted price of a token pair based on aggregated data from oracle nodes
    private func tokenPriceTrusted(fromid : TokenId, toid : TokenId) : ?TokenPriceOutput {

        var acc_price : Float = 0;
        var acc_liquidity : Float = 0;
        var buydepth2 : Float = 0;
        var buydepth8 : Float = 0;
        var buydepth50 : Float = 0;

        var volume : Float = 0;
        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;

            switch (pair.config) {
                case (#xrc(_))();
                case (_) continue pairs;
            };

            var rev = false;
            if (
                (pair.tokens.0 == fromid and pair.tokens.1 == toid) or (pair.tokens.1 == fromid and pair.tokens.0 == toid)
            ) {

                if (pair.tokens.0 == toid) {
                    rev := true;
                };

            } else {
                continue pairs;
            };

            switch (findLastPriceTick(pairid)) {
                case (?t) {

                    switch (rev) {
                        case (true) {
                            acc_price += 1 / ((t.2 + t.3) / 2);
                            acc_liquidity += 1;
                        };
                        case (false) {
                            acc_price += (t.2 + t.3) / 2;
                            acc_liquidity += 1;
                        };
                    };

                    volume += t.4;
                };
                case (null) {
                    continue pairs;
                };
            };
        };

        if (acc_liquidity == 0) return tokenPrice(fromid, toid);

        let price = acc_price / acc_liquidity;

        ?{ price; volume; buydepth2; buydepth8; buydepth50 };
    };

    // Calculates the price between two tokens which may not have a direct pair
    private func tokenPrice(fromid : TokenId, toid : TokenId) : ?TokenPriceOutput {

        var acc_price : Float = 0;
        var acc_liquidity : Float = 0;
        var volume : Float = 0;
        var buydepth2 : Float = 0;
        var buydepth8 : Float = 0;
        var buydepth50 : Float = 0;

        if (fromid == toid) return ?{
            price = 1 : Float;
            volume;
            buydepth2;
            buydepth8;
            buydepth50;
        };

        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;

            var rev = false;
            if (
                (pair.tokens.0 == fromid and pair.tokens.1 == toid) or (pair.tokens.1 == fromid and pair.tokens.0 == toid)
            ) {

                if (pair.tokens.0 == toid) {
                    rev := true;
                };

            } else {
                continue pairs;
            };

            switch (findLastPriceTick(pairid)) {
                case (?t) {

                    switch (rev) {
                        case (true) {
                            let liq : Float = 1; // + t.6[6];
                            acc_price += liq * (1 / ((t.2 + t.3) / 2));
                            acc_liquidity += liq;

                        };
                        case (false) {
                            let liq : Float = 1; // + t.5[6];
                            acc_price += liq * ((t.2 + t.3) / 2);
                            acc_liquidity += liq;

                        };
                    };

                    volume += t.4;
                };
                case (null) {
                    continue pairs;
                };
            };

            // 5 min ticks dont have depth to save memory
            switch (findLastPriceTick1h(pairid)) {
                case (?t) {

                    switch (rev) {
                        case (true) {

                            buydepth2 += t.6 [1];
                            buydepth8 += t.6 [3];
                            buydepth50 += t.6 [6];
                        };
                        case (false) {

                            buydepth2 += t.5 [1];
                            buydepth8 += t.5 [3];
                            buydepth50 += t.5 [6];
                        };
                    };

                };
                case (null) {
                    continue pairs;
                };
            };
        };

        if (acc_liquidity == 0) return null;

        let price = acc_price / acc_liquidity;

        ?{ price; volume; buydepth2; buydepth8; buydepth50 };
    };

    private func tokenPriceArray(fromid : TokenId, toid : TokenId, start : Nat, skip : Nat, tickcount : Nat) : ?[Float] {

        if (fromid == toid) return null;

        let targetPairs = Vector.new<(PairId, Bool)>();

        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;
            switch (pair.config) {
                case (#oracle(_)) continue pairs;
                case (_)();
            };
            var rev = false;
            if (
                (pair.tokens.0 == fromid and pair.tokens.1 == toid) or (pair.tokens.1 == fromid and pair.tokens.0 == toid)
            ) {

                if (pair.tokens.0 == toid) {
                    rev := true;
                };

            } else {
                continue pairs;
            };
            Vector.add(targetPairs, (pairid, rev));
        };

        let targetPairsArr = Vector.toArray(targetPairs);
        if (targetPairsArr.size() == 0) return null;

        ?Array.tabulate<Float>(
            tickcount,
            func(i) : Float {
                tokenPriceAtTick(targetPairsArr, start - i * skip);
            },
        );
    };

    // Calculates the price given pairs and tickIdx
    private func tokenPriceAtTick(pairs : [(PairId, Bool)], tickIdx : Nat) : Float {

        var acc_price : Float = 0;
        var acc_liquidity : Float = 0;

        label pairs for ((pairid, rev) in pairs.vals()) {
            switch (getTickItem(tickIdx, pairid)) {
                case (?t) {
                    switch (rev) {
                        case (true) {
                            acc_price += 1 * (1 / ((t.2 + t.3) / 2));
                            acc_liquidity += 1;
                        };
                        case (false) {
                            acc_price += 1 * ((t.2 + t.3) / 2);
                            acc_liquidity += 1;
                        };
                    };
                };
                case (null) {
                    continue pairs;
                };
            };
        };

        acc_price / acc_liquidity;

    };

    /// Retrieves the last price tick for a given pair ID within the 5-minute ticks
    /// Searches up to 50 ticks back
    private func findLastPriceTick(id : PairId) : ?TickItem {
        let last : Nat = Vector.size(ticks_5m) - 1;
        var cur : Nat = last;

        while (cur > 0) {
            let t = Vector.get<Tick>(ticks_5m, cur);
            if (t.size() > id) {
                switch (t[id]) {
                    case (?t) return ?t;
                    case (null)();
                };
            };
            cur -= 1;
            if (last > 50 + cur) return null;
        };

        return null;

    };

    // Retrieves the last price tick for a given pair ID within the 1-hour ticks
    // Searches up to 5 ticks back
    private func findLastPriceTick1h(id : PairId) : ?TickItem {
        let last : Nat = Vector.size(ticks_1h) - 1;
        var cur : Nat = last;

        while (cur > 0) {
            let t = Vector.get<Tick>(ticks_1h, cur);
            if (t.size() > id) {
                switch (t[id]) {
                    case (?t) return ?t;
                    case (null)();
                };
            };
            cur -= 1;
            if (last > 5 + cur) return null;
        };

        return null;

    };

    private func getTickItem(tickIdx : Nat, id : PairId) : ?TickItem {
        let t = Vector.get<Tick>(ticks_1h, tickIdx);
        if (t.size() <= id) return null;
        t[id];
    };

    // Oracle related variables
    stable var last_oracle_update : Time.Time = Time.now();

    // Oracles push values into a buffer that gets processed every 5 seconds
    var oracle_buffer = Vector.new<OracleIncoming>(); // raw oracle values

    // How many oracles are needed to produce a value
    let MIN_VALIDATORS = 1;

    // Array of oracle stream identifiers used in the system
    let oracle_streams : [Text] = ["BTC/USD", "ICP/USD", "ETH/USD", "ICP-CS", "ICP/USD-V24", "BTC-CS", "BTC-TS", "BTC/USD-V24", "ETH-CS", "ETH-TS", "ETH/USD-V24"];

    // Stores the latest oracle values for different streams after processing
    var oracle_latest : [(Text, Float)] = []; // oracle values get placed here after processing and later stored or used

    // Retrieves the last value for a given oracle key if available
    private func last_oracle_value(key : Text) : ?Float {

        let ?rez = Array.find(
            oracle_latest,
            func(x : (Text, Float)) : Bool {
                x.0 == key;
            },
        ) else return null;

        ?rez.1;
    };

    // Searches for the last available token tick for a given token ID
    // If it's not available within the last 365 days, returns null
    private func findLastTokenTick(id : TokenId) : ?TokenTickItem {
        let last : Nat = Vector.size(token_ticks_1d) - 1;
        var cur : Nat = last;

        while (cur > 0) {
            let t = Vector.get<TokenTick>(token_ticks_1d, cur);
            if (t.size() > id) {
                switch (t[id]) {
                    case (?t) return ?t;
                    case (null)();
                };
            };
            cur -= 1;
            if (last > 356 + cur) return null; // search max 365 ticks back
        };

        return null;

    };

    // Gets the token tick store and seconds for a given Frame
    private func f2t(f : Frame) : (Vector.Vector<Tick>, Nat) {
        switch (f) {
            case (#t5m)(ticks_5m, 5 * 60);
            case (#t1h)(ticks_1h, 60 * 60);
            case (#t1d)(ticks_1d, 60 * 60 * 24);
        };
    };

    // Exports pair data for a given frame and pairId
    public shared ({ caller }) func controller_export_pair(f : Frame, from : Time.Time, pairid : Nat, size : Nat) : async [?TickItem] {
        //assert(Principal.isController(caller));
        assert caller == adminPrincipal;

        let (ticks, tsec) = f2t(f);
        var idx = 0;
        var rez = Vector.new<?TickItem>();

        let fromTick : Nat = (Int.abs(from) - Int.abs(first_tick)) / (1000000000 * tsec);

        while (idx < size) {
            let tx = Vector.get<Tick>(ticks, fromTick + idx);
            Vector.add(rez, tx[pairid]);

            idx += 1;
        };

        Vector.toArray(rez);
    };

    private func tick_resize_if_needed<A>(arr : [var ?A], newlen : Nat) : [var ?A] {
        var psize = arr.size();
        if (newlen <= psize) return arr;

        let newarr = Array.init<?A>(newlen, null);
        for (idx in arr.keys()) {
            newarr[idx] := arr[idx];
        };
        newarr;
    };

    private func import_pair(f : Frame, from : Time.Time, pairid : Nat, data : [?TickItem], mode : { #add; #overwrite }) : () {
        let (ticks, tsec) = f2t(f);
        let fromTick : Nat = (Int.abs(from) - Int.abs(first_tick)) / (1000000000 * tsec);

        var idx = 0;
        for (t in data.vals()) {

            // handle the case when there aren't enough pair slots inside the tick
            var used = tick_resize_if_needed(Vector.get<Tick>(ticks, fromTick + idx), pairid +1);
            switch (mode) {
                case (#overwrite) {
                    used[pairid] := t;
                    Vector.put<Tick>(ticks, fromTick + idx, used);
                };
                case (#add) {
                    if (Option.isNull(used[pairid])) {
                        used[pairid] := t;
                        Vector.put<Tick>(ticks, fromTick + idx, used);
                    };
                };
            };

            idx += 1;
        };
    };

    // Imports pair data for a given frame and pairId
    public shared ({ caller }) func controller_import_pair(f : Frame, from : Time.Time, pairid : Nat, data : [?TickItem], mode : { #add; #overwrite }) : async () {
        // assert(Principal.isController(caller));
        assert caller == adminPrincipal;
        import_pair(f, from, pairid, data, mode);

    };

    type GetPairsResult = Result.Result<{ data : [TickShared]; first : Time.Time; last : Time.Time; updated : Time.Time }, GetError>;
    /// Retrieves pair data for specified frames and time range
    public query func get_pairs(f : Frame, ids : [Nat], from : ?Time.Time, to : ?Time.Time) : async GetPairsResult {
        let ft = first_tick;
        let (ticks, tsec) = f2t(f);
        let fromTick : Nat = (Int.abs(switch (from) { case (?t) t; case (null) ft }) - Int.abs(ft)) / (1000000000 * tsec);
        var toTick : Nat = (Int.abs(switch (to) { case (?t) t; case (null) Time.now() }) - Int.abs(ft)) / (1000000000 * tsec);
        let max = Vector.size(ticks);
        if (toTick >= max) toTick := max -1;
        let ticks_asked : Nat = toTick - fromTick + 1;
        if (ticks_asked > 8641) return #err(#invalid_frame);

        let data = switch (ids.size() == 0) {
            case (true) {
                Array.tabulate<TickShared>(
                    ticks_asked,
                    func(i) : TickShared {
                        Array.freeze(Vector.get<Tick>(ticks, fromTick + i));
                    },
                );
            };
            case (false) {
                Array.tabulate<TickShared>(
                    ticks_asked,
                    func(i) : TickShared {
                        let tick = Vector.get<Tick>(ticks, fromTick + i);
                        Array.tabulate(
                            ids.size(),
                            func(idx : Nat) : ?TickItem {
                                if (ids[idx] >= tick.size()) return null;
                                tick[ids[idx]];
                            },
                        );
                    },
                );
            };
        };

        let last : Time.Time = ft + (toTick * tsec * 1000000000); // You get the start time of the last candle
        let first : Time.Time = ft + (fromTick * tsec * 1000000000); // You get the start time of the first candle
        #ok({ data; first; last; updated = last_update });
    };

    type GetTokensResult = Result.Result<{ data : [TokenTickShared]; first : Time.Time; last : Time.Time; updated : Time.Time }, GetError>;
    // Retrieves token data for specified frames and time range
    public query func get_tokens(ids : [Nat], from : ?Time.Time, to : ?Time.Time) : async GetTokensResult {
        let ft = first_tick;
        let (ticks, tsec) = (token_ticks_1d, 60 * 60 * 24);
        let fromTick : Nat = (Int.abs(switch (from) { case (?t) t; case (null) ft }) - Int.abs(ft)) / (1000000000 * tsec);
        var toTick : Nat = (Int.abs(switch (to) { case (?t) t; case (null) Time.now() }) - Int.abs(ft)) / (1000000000 * tsec);
        let max = Vector.size(ticks);
        if (toTick >= max) toTick := max - 1;
        let ticks_asked : Nat = toTick - fromTick + 1;
        if (ticks_asked > 8642) return #err(#invalid_frame);

        let data = switch (ids.size() == 0) {
            case (true) {
                Array.tabulate<TokenTickShared>(
                    ticks_asked,
                    func(i) : TokenTickShared {
                        Array.freeze(Vector.get<TokenTick>(ticks, fromTick + i));
                    },
                );
            };
            case (false) {
                Array.tabulate<TokenTickShared>(
                    ticks_asked,
                    func(i) : TokenTickShared {
                        let tick = Vector.get<TokenTick>(ticks, fromTick + i);
                        Array.tabulate(
                            ids.size(),
                            func(idx : Nat) : ?TokenTickItem {
                                if (ids[idx] >= tick.size()) return null;
                                tick[ids[idx]];
                            },
                        );
                    },
                );
            };
        };

        let last : Time.Time = ft + (toTick * tsec * 1000000000); // You get the start time of the last candle
        let first : Time.Time = ft + (fromTick * tsec * 1000000000); // You get the start time of the first candle
        #ok({ data; first; last; updated = last_update });
    };

    // Stores pair tick information
    private func put_tick(ticks : Vector.Vector<Tick>, currentTick : Nat, (pairid, lastbid, lastask, volume, depthBid50, depthAsk50) : TickLast) : () {
        switch (Vector.getOpt<Tick>(ticks, currentTick)) {
            case (null) {
                //handle a case when ticks are missing
                var vsize = Vector.size(ticks);
                while (vsize <= currentTick) {
                    Vector.add<Tick>(ticks, Array.init<?TickItem>(Vector.size(pair_config), null));
                    vsize := Vector.size(ticks);
                };

                let tt = Vector.get<Tick>(ticks, currentTick);
                tt[pairid] := ?(lastbid, lastbid, lastbid, lastask, volume, depthBid50, depthAsk50);

            };
            case (?p) {
                // update

                // handle the edge cases when you add a new pair and there is no slot for it inside the tick
                var used = p;

                var psize = p.size();
                if (pairid >= psize) {
                    // recreate larger array
                    used := Array.init<?TickItem>(Vector.size(pair_config), null);
                    for (idx in Vector.get<Tick>(ticks, currentTick).keys()) {
                        used[idx] := p[idx];
                    };
                    Vector.put<Tick>(ticks, currentTick, used);
                };

                let high = switch (used[pairid]) {
                    case (null) lastbid;
                    case (?c) {
                        if (c.1 < lastbid) lastbid else c.1;
                    };
                };

                let low = switch (used[pairid]) {
                    case (null) lastbid;
                    case (?c) {
                        if (c.1 > lastbid) lastbid else c.1;
                    };
                };

                used[pairid] := ?(high, low, lastbid, lastask, volume, depthBid50, depthAsk50);

            };
        };
    };

    // Updates tick information for pairs configured to use the ICPSwap service
    private func icpswap() : async () {

        let root : ICPSwapRoot.Self = actor ("ggzvv-5qaaa-aaaag-qck7a-cai");
        let pd_promise = root.getAllPools();
        
        let tvlcan : ICPSwap.Self = actor ("gp26j-lyaaa-aaaag-qck6q-cai");
        let tvl = await tvlcan.getAllPoolTvl();
        let pd = await pd_promise;

        let ft : Time.Time = first_tick;
        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;
            switch (pair.config) {
                case (#icpswap({ canister })) {
                    let token_first = Vector.get(tokens, pair.tokens.0);
                    // find data in pd;
                    let tcanister = Principal.toText(canister);
                    let ?info = Array.find(
                        pd,
                        func(x : ICPSwapRoot.PublicPoolOverView) : Bool {
                            x.pool == tcanister;
                        },
                    ) else continue pairs;

                    let volume = info.volumeUSD;
                    let (t0p, t1p) = switch (info.token0Symbol == token_first.symbol) {
                        case (true)(info.token0Price, info.token1Price);
                        case (false)(info.token1Price, info.token0Price);
                    };

                    let price = t0p / t1p;

                    let tvlUsd : Float = switch (
                        Array.find(
                            tvl,
                            func(x : (Text, Float)) : Bool {
                                x.0 == tcanister;
                            },
                        )
                    ) {
                        case (?f) f.1;
                        case (null) 0;
                    };

                    let liq_buy = (tvlUsd / t0p) / 4;
                    let liq_sell = (tvlUsd / t1p) / 4;

                    let t : TickLast = (
                        pairid,
                        price,
                        price,
                        volume,
                        [liq_buy * 0.02, liq_buy * 0.04, liq_buy * 0.08, liq_buy * 0.16, liq_buy * 0.3, liq_buy / 2, liq_buy, liq_buy * 2],
                        [liq_sell * 0.02, liq_sell * 0.04, liq_sell * 0.08, liq_sell * 0.16, liq_sell * 0.3, liq_sell / 2, liq_sell, liq_sell * 2],
                    );
                    put_tick(ticks_5m, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 5), stripDepth(t));
                    put_tick(ticks_1h, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60), t);
                    put_tick(ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), t);

                };
                case (_) continue pairs;
            };
        };

    };

    // Remove the depth from a tick
    private func stripDepth(t : TickLast) : TickLast {
        //(PairId, LastBid, LastAsk, Volume24, DepthBid50, DepthAsk50)
        (t.0, t.1, t.2, t.3, [], []);
    };

    // Collect Sonic pair data
    private func sonic() : async () {

        let root : Sonic.Self = actor ("3xwpq-ziaaa-aaaah-qcn4a-cai");
        let pd = await root.getAllPairs();

        let sonicvol : SonicVol.Self = actor ("eld2c-oyaaa-aaaai-qpdra-cai");
        let volumes = await sonicvol.getPairVolumes();

        let ft : Time.Time = first_tick;

        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;
            switch (pair.config) {
                case (#sonic({ id })) {
                    let token_first = Vector.get(tokens, pair.tokens.0);
                    let token_second = Vector.get(tokens, pair.tokens.1);

                    // find data in pd;
                    let ?info = Array.find(
                        pd,
                        func(x : Sonic.PairInfoExt) : Bool {
                            x.id == id;
                        },
                    ) else continue pairs;

                    let zeroPrice : TokenPriceOutput = {
                        price = 0;
                        volume = 0;
                        buydepth2 = 0;
                        buydepth8 = 0;
                        buydepth50 = 0;
                    };

                    let volume : Float = switch (
                        Array.find(
                            volumes,
                            func(x : (Text, Nat, Nat)) : Bool {
                                x.0 == id;
                            },
                        )
                    ) {
                        case (?x) {
                            let Icp2Usd = Option.get(tokenPriceTrusted(ICP, USD), zeroPrice);
                            let token2Icp = Option.get(tokenPrice(pair.tokens.0, ICP), zeroPrice);
                            (Float.fromInt(x.1 / (10 ** (token_first.decimals - 4))) / (10 ** 4)) * token2Icp.price * Icp2Usd.price;
                        };
                        case (null) 0 : Float;
                    };

                    let r0 = Float.fromInt(info.reserve0 / (10 ** (token_first.decimals - 4)));
                    let r1 = Float.fromInt(info.reserve1 / (10 ** (token_second.decimals - 4)));

                    let price = (r1 / r0);

                    // let liquidity = info.reserve0 / (10 ** token_first.decimals);
                    let liq_buy = (Float.fromInt(info.reserve0) / Float.fromInt(10 ** token_first.decimals)) / 2;
                    let liq_sell = (Float.fromInt(info.reserve1) / Float.fromInt(10 ** token_second.decimals)) / 2;

                    let t : TickLast = (
                        pairid,
                        price,
                        price,
                        volume,
                        [liq_buy * 0.02, liq_buy * 0.04, liq_buy * 0.08, liq_buy * 0.16, liq_buy * 0.3, liq_buy / 2, liq_buy, liq_buy * 2],
                        [liq_sell * 0.02, liq_sell * 0.04, liq_sell * 0.08, liq_sell * 0.16, liq_sell * 0.3, liq_sell / 2, liq_sell, liq_sell * 2],
                    );
                    put_tick(ticks_5m, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 5), stripDepth(t));
                    put_tick(ticks_1h, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60), t);
                    put_tick(ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), t);

                };
                case (_) continue pairs;
            };
        };

    };

    // Collect ICDex pair data
    private func icdex(pairid : PairId, canister : Principal) : async TickLast {
        let pc = Vector.get(pair_config, pairid);

        let token_first = Vector.get(tokens, pc.tokens.0);
        let token_second = Vector.get(tokens, pc.tokens.1);

        let can : ICDex.Self = actor (Principal.toText(canister));
        let promise1 = can.stats();
        let promise2 = can.level100();
        let st = await promise1;
        let volume = st.vol24h.value0;

        let lvl = await promise2;

        let decimals = Float.fromInt(lvl.0);
        // BID

        let bid_price : Float = Float.fromInt(lvl.1.bid[0].price) / decimals;
        let bid_mid_price : Nat = lvl.1.bid[0].price / 2;

        var depthBid50 : Float = 0;
        label liquid for (bid in lvl.1.bid.vals()) {
            if (bid.price < bid_mid_price) {
                break liquid;
            };
            depthBid50 += Float.fromInt(bid.quantity) // Notice: Perhaps we shouldn't store it token0 - all bids and asks should be in token1
        };

        // ASK
        let ask_price : Float = Float.fromInt(lvl.1.ask[0].price) / decimals;
        let ask_mid_price : Nat = lvl.1.ask[0].price * 2;

        var depthAsk50 : Float = 0;
        label liquid for (ask in lvl.1.ask.vals()) {
            if (ask.price > ask_mid_price) {
                break liquid;
            };
            depthAsk50 += Float.fromInt(ask.quantity) * (Float.fromInt(ask.price) / decimals);
        };

        let volumeToken = (Float.fromInt(volume) / 10 ** (Float.fromInt(token_first.decimals)));

        let zeroPrice : TokenPriceOutput = {
            price = 0;
            volume = 0;
            buydepth2 = 0;
            buydepth8 = 0;
            buydepth50 = 0;
        };

        let volumeUsd = switch (pc.tokens.0 == 3) {
            case (true) {
                let Icp2Usd = Option.get(tokenPriceTrusted(ICP, USD), zeroPrice);
                volumeToken * Icp2Usd.price;
            };
            case (false) {
                let token2Icp = switch (pc.tokens.1 == 3) {
                    case (true)(bid_price + ask_price) / 2;
                    case (false) Option.get(tokenPriceTrusted(pc.tokens.0, USD), zeroPrice).price;
                };

                let Icp2Usd = Option.get(tokenPriceTrusted(ICP, USD), zeroPrice);
                volumeToken * token2Icp * Icp2Usd.price;
            };
        };

        let liq_buy = depthBid50 / 10 ** Float.fromInt(token_first.decimals);
        let liq_sell = depthAsk50 / 10 ** Float.fromInt(token_second.decimals);

        (
            pairid,
            bid_price,
            ask_price,
            volumeUsd,
            [liq_buy * 0.02, liq_buy * 0.04, liq_buy * 0.08, liq_buy * 0.16, liq_buy * 0.3, liq_buy / 2, liq_buy, liq_buy * 2],
            [liq_sell * 0.02, liq_sell * 0.04, liq_sell * 0.08, liq_sell * 0.16, liq_sell * 0.3, liq_sell / 2, liq_sell, liq_sell * 2],
        );

    };

    // Adds an error to the error log
    private func logErr(desc : Text, e : Error.Error) : () {
        ignore errorsLog.add((Time.now(), desc, Error.code(e), Error.message(e)));
        if (errorsLog.len() > 500) {
            errorsLog.delete(1);
        };
    };

    // Displays the error log entries
    public query func log_show() : async [?ErrorLine] {
        let start = errorsLog.start();
        Array.tabulate(
            errorsLog.len(),
            func(i : Nat) : ?ErrorLine {
                errorsLog.getOpt(start + i);
            },
        );
    };

    let requests = Subject<PairId>();

    // Create reactive stream for token tick retrieval and processing
    ignore pipe3(
        requests,
        bufferTime<PairId>(3, 20), // every X seconds push Y items
        // if you try more than 25 concurrent calls
        // your playground canister will need more cycles
        mapAsync<system, [PairId], TickLast>(
            // you get non-shared error when trying to return something generic from async
            // instead we are providing a function where you can push it
            func<system>(x : [PairId], next : <system>(TickLast) -> ()) : async () {
                // this can't be tucked inside a library, because of non-shared error
                // you can't have a List of <async T>

                // Prepare a list to hold PairId and corresponding async operation
                var buf = List.nil<(PairId, async TickLast)>();
                label pair for (pairid in x.vals()) {
                    // make the calls

                    let pc = Vector.get(pair_config, pairid);
                    let promise = switch (pc.config) {
                        // Based on configuration, determine the async operation
                        case (#icdex({ canister })) {
                            icdex(pairid, canister);
                        };
                        case (_) continue pair;
                    };

                    buf := List.push((pairid, promise), buf); // Add the PairId and its promise to the list

                };

                label awaitpair for ((id, promise) in List.toIter(buf)) {
                    // Await results of all promises
                    try {
                        let pairlast = await promise; // Await the promise to get the tick data
                        next<system>(pairlast); // Send the tick data to the next stage of processing
                    } catch e {
                        logErr("collecting pair " # debug_show ({ id }), e); // Log error if any promise fails
                    };
                };

            },
        ),
    ).subscribe<system>({
        // Handle the output of the stream
        next = func<system>(t : TickLast) {
            let ft : Time.Time = first_tick;

            // Update different tick datasets with the new tick data
            put_tick(ticks_5m, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 5), stripDepth(t));
            put_tick(ticks_1h, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60), t);
            put_tick(ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), t);
            last_update := Time.now(); // Update the last update time
        };
        complete = null_func;
    });

    // Collects token data and initiates token request for updating token ticks
    private func token_collect<system>() : () {

        label tloop for ((token, tokenid) in Vector.items(tokens)) {
            if (token.deleted == true) continue tloop;
            token_requests.next<system>(tokenid);
        };

    };

    // ICP ledger actor
    let ledgerICP = actor ("ryjl3-tyaaa-aaaaa-aaaba-cai") : ICRC1.Self;

    private func token_dip20(_tokenId : Nat, leder : Principal) : async ?TokenTickItem {
        let ledger : DIP20.Self = actor (Principal.toText(leder));

        let meta = await ledger.getMetadata();

        ?{
            circulating_supply = meta.totalSupply;
            total_supply = meta.totalSupply;
            fee = meta.fee;
            locking = null;
        };
    };

    // Collect tick information for icrc1 tokens
    private func token_icrc1(tokenId : Nat, leder : Principal, locking : TokenLocking) : async ?TokenTickItem {

        let ledger : ICRC1.Self = actor (Principal.toText(leder));

        let fee = await ledger.icrc1_fee();
        let total_supply = await ledger.icrc1_total_supply();

        let circulating_supply : Nat = switch (locking) {

            case (#none) {
                switch (tokenId == ICP) {
                    case (false) total_supply;
                    case (true) {
                        Int.abs(Float.toInt(Option.get(last_oracle_value("ICP-CS"), 0 : Float))) * 10 ** 8;
                    };
                };
            };
            case (#ogy) {
                await Ogy.get(total_supply);
            };
            case (#sns(cfg)) {

                let treasury : Nat = await ledger.icrc1_balance_of({
                    owner = cfg.governance;
                    subaccount = ?cfg.treasury_subaccount;
                });

                let treasuryICP : Nat = await ledgerICP.icrc1_balance_of({
                    owner = cfg.governance;
                    subaccount = null;
                });

                var total_locked = 0;

                let sout : LockingVarTick = {
                    other_treasuries = [(ICP, treasuryICP)];
                    treasury;
                    var total_locked = total_locked;
                    dissolving = Array.init<Nat>(365, 0);
                    not_dissolving = Array.init<Nat>(365, 0);
                };

                let circulating_supply : Nat = total_supply - treasury - total_locked;

                neuron_mine<system>(cfg, tokenId, sout, null, { circulating_supply; total_supply; fee; locking = null });

                return null;
            };
        };

        ?{ circulating_supply; total_supply; fee; locking = null };

    };

    // Place token tick information into the token tick store
    private func put_token_tick(ticks : Vector.Vector<TokenTick>, currentTick : Nat, tokenid : TokenId, t : TokenTickItem) : () {
        switch (Vector.getOpt<TokenTick>(ticks, currentTick)) {
            case (null) {

                //handle a case when ticks are missing
                var vsize = Vector.size(ticks);
                while (vsize <= currentTick) {
                    Vector.add<TokenTick>(ticks, Array.init<?TokenTickItem>(Vector.size(tokens), null)); //
                    vsize := Vector.size(ticks);
                };

                let tt = Vector.get<TokenTick>(ticks, currentTick);
                tt[tokenid] := ?t;

            };
            case (?p) {
                // update

                // handle the edge cases when you add a new pair and there is no slot for it inside the tick
                var used = p;

                var psize = p.size();
                if (tokenid >= psize) {
                    // recreate larger array
                    used := Array.init<?TokenTickItem>(Vector.size(tokens), null);
                    for (idx in p.keys()) {
                        used[idx] := p[idx];
                    };
                    Vector.put<TokenTick>(ticks, currentTick, used);
                };

                used[tokenid] := ?t;
            };
        };
    };

    let yearinseconds : Nat = 60 * 60 * 24 * 365; // 1 year in seconds

    // Start async process for collecting neuron data
    private func neuron_mine<system>(cfg : SnsConfig, tokenId : Nat, sout : LockingVarTick, inc_last_id : ?SNSGov.NeuronId, tickInfo : TokenTickItem) : () {

        ignore Timer.setTimer<system>(
            #seconds 0,
            func() : async () {
                try {
                    await neuron_mine_internal(cfg, tokenId, sout, inc_last_id, tickInfo); // We need to wrap this because Motoko won't throw errors unless they are in async function
                } catch e {
                    logErr("collecting neuron " # debug_show ({ tokenId }), e);
                };
            },
        );
    };

    // Collects neuron data and calculates token tick information
    private func neuron_mine_internal(cfg : SnsConfig, tokenId : Nat, sout : LockingVarTick, inc_last_id : ?SNSGov.NeuronId, tickInfo : TokenTickItem) : async () {
        var last_id : ?SNSGov.NeuronId = inc_last_id;
        var finished : Bool = false;

        let gov : SNSGov.Self = actor (Principal.toText(cfg.governance));
        var idx = 0;
        let now : Nat = Int.abs(Time.now() / 1000000000);
        label scan loop {
            let r = await gov.list_neurons({
                of_principal = null;
                limit = 100;
                start_page_at = last_id;
            });

            // dbgCounter[tokenId] += 1;

            label neuronloop for (n in r.neurons.vals()) {
                var dissolve_time = now;

                let dissolving = switch (n.dissolve_state) {
                    case (? #DissolveDelaySeconds(s)) {
                        dissolve_time += Nat64.toNat(s);
                        false;
                    };
                    case (? #WhenDissolvedTimestampSeconds(ts)) {
                        let t = Nat64.toNat(ts);
                        if (t > now) {
                            dissolve_time := t;
                            true;
                        } else {
                            false;
                        };
                    };
                    case (null) true;
                };

                let bal = Nat64.toNat(n.cached_neuron_stake_e8s);

                if (bal == 0) continue neuronloop;

                sout.total_locked += bal;

                if (dissolve_time > (now + yearinseconds - 86400 : Nat)) continue neuronloop;

                let dissolve_day : Nat = switch ((dissolve_time < now)) {
                    case (true) 0 : Nat;
                    case (false)(dissolve_time - now) / 86400 : Nat;
                };

                if (dissolving) {
                    sout.dissolving[dissolve_day] += bal;
                } else {
                    sout.not_dissolving[dissolve_day] += bal;
                };
            };

            if (r.neurons.size() < 100) {

                finished := true;
                break scan;
            };

            last_id := r.neurons[99].id;

            if (idx > 5) {
                // Collecting only 5 * 100 neurons, the remaining are collected in with another setTimer
                break scan;
            };

            idx += 1;
        };

        if (finished) {
            // Calculate and update
            sout.total_locked -= sout.not_dissolving[0];

            let t : TokenTickItem = {
                tickInfo with
                locking = ?{
                    treasury = sout.treasury;
                    other_treasuries = sout.other_treasuries;
                    total_locked = sout.total_locked;
                    dissolving = Array.freeze(sout.dissolving);
                    not_dissolving = Array.freeze(sout.not_dissolving);
                };
            };

            put_token_tick(token_ticks_1d, (Int.abs(Time.now()) - Int.abs(first_tick)) / (1000000000 * 60 * 60 * 24), tokenId, t);

        } else {
            neuron_mine<system>(cfg, tokenId, sout, last_id, tickInfo);
        };

    };

    let token_requests = Subject<TokenId>();

    // Create reactive stream for token tick retrieval and processing
    ignore pipe3(
        token_requests,
        bufferTime<TokenId>(5, 3), // every X seconds push Y items
        // if you try more than 25 concurrent calls
        // your playground canister will need more cycles
        mapAsync<system, [TokenId], (TokenId, TokenTickItem)>(
            // you non-shared error when trying to return something generic from async
            // instead we are providing a function where you can push it
            func(x : [TokenId], next : <system>((TokenId, TokenTickItem)) -> ()) : async () {

                // this can't be tucked inside a library, because of non-shared error
                // you can't have a List of <async T>
                var buf = List.nil<(TokenId, async ?TokenTickItem)>();
                label tloop for (tokenid in x.vals()) {
                    // make the calls

                    let token = Vector.get(tokens, tokenid); // Get the token configuration

                    let promise = switch (token.ledger) {
                        // Based on configuration, determine the async operation
                        case (#icrc1({ ledger })) {
                            token_icrc1(tokenid, ledger, token.locking);
                        };
                        case (#dip20({ ledger })) {
                            token_dip20(tokenid, ledger);
                        };
                        case (_) continue tloop;
                    };

                    buf := List.push((tokenid, promise), buf); // Add the PairId and its promise to the list
                };

                for ((id, promise) in List.toIter(buf)) {
                    // Await results of all promises
                    try {
                        switch (await promise) {
                            case (?a) next<system>(id, a); // Send the tick data to the next stage of processing
                            case (null)();
                        };
                    } catch e {
                        logErr("collecting token " # debug_show ({ id }), e);
                    };
                };

            },
        ),
    ).subscribe<system>({
        // Handle the output of the stream
        next = func<system>((id:Nat ,t:TokenTickItem)) {
            let ft : Time.Time = first_tick;

            // Update different tick datasets with the new tick data
            put_token_tick(token_ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), id, t);

            last_update := Time.now(); // Update the last update time
        };
        complete = null_func;
    });

    /// Sets up a recurring timer to collect pair data every 20 seconds
    ignore Timer.recurringTimer<system>(
        #seconds 2,
        func() : async () {

            // ICDEX data comes from multiple canisters and therefore is passed to the stream processor
            label pairs for ((pair, pairid) in Vector.items(pair_config)) {
                if (pair.deleted == true) continue pairs;
                switch (pair.config) {
                    case (#icdex(_)) {
                        requests.next<system>(pairid);
                    };
                    case (_) continue pairs;
                };
            };

            // ICPSwap data comes from a single canister
            try {
                await icpswap();
            } catch e {
                logErr("collecting icpswap", e);
            };

            // Sonic data comes from a single canister
            try {
                await sonic();
            } catch e {
                logErr("collecting sonic_", e);
            };

        },
    );

    // Sets up a recurring timer to collect token data every 12 hours
    ignore Timer.recurringTimer<system>(
        #seconds 43200,
        func() : async () {
            token_collect<system>();
        },
    );

    // Oracle
    // Oracles are deprecated and will be replaced with HTTP Outcalls
    // Currently they are only used for total and circulating supply for BTC, ETH, ICP
    type OracleIncoming = { from : Principal; data : [(Text, Float)] };

    type OraclePushError = {
        #not_in_validator_set;
        #too_early;
    };

    /// Adds a new oracle node to the system with the given name and principal
    public shared ({ caller }) func controller_oracle_add(name : Text, node_principal : Principal) : async Result.Result<(), Text> {
        //assert(Principal.isController(caller));
        assert caller == adminPrincipal;
        let rv = BTree.get(nodes, Principal.compare, node_principal);
        switch (rv) {
            case (null) {
                let node : NodeInfo = {
                    var good = 0;
                    var bad = 0;
                    var last = 0;
                    name = name;
                };
                ignore BTree.insert<Principal, NodeInfo>(nodes, Principal.compare, node_principal, node);
                #ok();
            };
            case (?n) #err("Already exists");
        };
    };

    public shared ({ caller }) func controller_oracle_rem(node_principal : Principal) : async Result.Result<(), Text> {
        // assert(Principal.isController(caller));
        assert caller == adminPrincipal;
        let rv = BTree.get(nodes, Principal.compare, node_principal);
        switch (rv) {
            case (null) #err("Not found");
            case (?n) {
                ignore BTree.delete<Principal, NodeInfo>(nodes, Principal.compare, node_principal);
                #ok();
            };
        };
    };

    // Function for oracles to push data, validates the data's timeliness and the node's validity
    public shared ({ caller }) func oracle_push({ data : [(Text, Float)] }) : async Result.Result<Time.Time, OraclePushError> {
        // Check if caller is in validator set and if their last update is more than 4.9 sec ago
        let ?node = BTree.get(nodes, Principal.compare, caller) else return #err(#not_in_validator_set);
        if (node.last + 2000000000 > Time.now()) return #err(#too_early);
        node.last := Time.now();

        oracle_buffer := Vector.new<OracleIncoming>(); // clear in case of error
        Vector.add(oracle_buffer, { from = caller; data });

        // Was in timer before, but is not needed with 1 oracle
        oracle_buffer_digest();
        oracle_pairs_distribute();
        oracle_tokens_distribute();

        #ok(node.last - last_oracle_update); // returned for sync purposes
    };

    // Returns oracle stats
    public query func oracles_get() : async [NodeInfoShared] {
        Array.map(
            BTree.toArray(nodes),
            func(x : (Principal, NodeInfo)) : NodeInfoShared {
                {
                    principal = x.0;
                    good = x.1.good;
                    bad = x.1.bad;
                    last = x.1.last;
                    name = x.1.name;
                };
            },
        );
    };

    // Processes the buffered oracle data to update latest values and validate node contributions
    private func oracle_buffer_digest() : () {
        let udata = Vector.toArray(oracle_buffer);
        let orez = Vector.new<(Text, Float)>();
        if (udata.size() < MIN_VALIDATORS) return ();

        label oraclestreams for ((id) in oracle_streams.vals()) {

            let stdinput = Array.mapFilter<OracleIncoming, Float>(
                udata,
                func(x : OracleIncoming) : ?Float {
                    // find if pair exists
                    let d = Array.find(
                        x.data,
                        func(y : (Text, Float)) : Bool {
                            y.0 == id;
                        },
                    );
                    switch (d) {
                        case (null) null;
                        case (?d) ?d.1;
                    };
                },
            );

            if (stdinput.size() == 0) continue oraclestreams;

            let (mean, std) = clean_std(stdinput);

            label reward for ({ from; data } in udata.vals()) {
                let d = Array.find(
                    data,
                    func(y : (Text, Float)) : Bool {
                        y.0 == id;
                    },
                );
                switch (d) {
                    case (null) continue reward;
                    case (?d) {
                        // if an outlier, then penalize
                        let ?node = BTree.get(nodes, Principal.compare, from) else continue reward;
                        if (d.1 > mean + std * 2 or d.1 < mean - std * 2) {
                            node.bad += 1;
                        } else {
                            node.good += 1;
                        };

                    };
                };
            };

            Vector.add(orez, (id, mean));
        };

        oracle_latest := Vector.toArray(orez);

        last_oracle_update := Time.now();
        last_update := Time.now();

        // clear buffer
        oracle_buffer := Vector.new<OracleIncoming>();
    };

    // Processes the buffered oracle data to update latest values and validate node contributions
    private func oracle_pairs_distribute() : () {
        let ft : Time.Time = first_tick;

        label pairs for ((pair, pairid) in Vector.items(pair_config)) {
            if (pair.deleted == true) continue pairs;
            switch (pair.config) {
                case (#oracle({ id })) {

                    let ?val = last_oracle_value(id) else continue pairs;

                    let token_first = Vector.get(tokens, pair.tokens.0);
                    let token_second = Vector.get(tokens, pair.tokens.1);

                    let volume = Option.get(last_oracle_value(token_first.symbol # "/" # token_second.symbol # "-V24"), 0 : Float);
                    // add tick
                    let t : TickLast = (
                        pairid,
                        val,
                        val,
                        volume,
                        [0, 0, 0, 0, 0, 0, 0, 0],
                        [0, 0, 0, 0, 0, 0, 0, 0],
                    );

                    put_tick(ticks_5m, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 5), stripDepth(t));
                    put_tick(ticks_1h, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60), t);
                    put_tick(ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), t);

                };
                case (_) continue pairs;
            };
        };
    };

    // Processes the buffered oracle data to update latest values and validate node contributions
    private func oracle_tokens_distribute() : () {
        let ft : Time.Time = first_tick;

        label tokensloop for ((token, tokenid) in Vector.items(tokens)) {
            if (token.deleted == true) continue tokensloop;
            if (tokenid != BTC and tokenid != ETH) continue tokensloop;

            let ?cs = last_oracle_value(token.symbol # "-CS") else continue tokensloop;
            let ?ts = last_oracle_value(token.symbol # "-TS") else continue tokensloop;
            let circulating_supply = Int.abs(Float.toInt(cs)) * 10 ** token.decimals;
            let total_supply = Int.abs(Float.toInt(ts)) * 10 ** token.decimals;

            // add tick
            let t : TokenTickItem = {
                fee = 0;
                circulating_supply;
                total_supply;
                locking = null;
            };

            put_token_tick(token_ticks_1d, (Int.abs(Time.now()) - Int.abs(ft)) / (1000000000 * 60 * 60 * 24), tokenid, t);

        };
    };

    /* Removed because currently only one oracle is needed, but useful to keep the code around

    private func _oracle_timer() : async () {
        oracle_buffer_digest();
        oracle_pairs_distribute();
        oracle_tokens_distribute();
    };

    ignore Timer.recurringTimer( #seconds 5, func() : async () {
        try {
            await _oracle_timer();
        } catch e {
            logErr("oracle timerx ", e);
        };
    });

    */

    type LatestTokenRow = ((TokenId, TokenId), Text, Float);

    /// Retrieves the latest exchange rate information for each token pair
    public query func get_latest() : async [LatestTokenRow] {
        let rez = Vector.new<LatestTokenRow>();

        let ?Icp2Usd = tokenPriceTrusted(ICP, USD) else Debug.trap("ICP2USD rate not available");

        label tloop for ((token, tokenid) in Vector.items(tokens)) {
            if (token.deleted == true) continue tloop;

            let symbol = token.symbol;
            if (tokenid == USD) continue tloop; // skip USD
            if (tokenid != ICP) switch (tokenPrice(tokenid, ICP)) {
                case (?priceIcp) {
                    if (tokenid != XDR) Vector.add<LatestTokenRow>(rez, ((tokenid, ICP), symbol # "/ICP", priceIcp.price));
                    Vector.add<LatestTokenRow>(rez, ((tokenid, USD), symbol # "/USD", priceIcp.price * Icp2Usd.price));
                };
                case (null)();
            };

            if (tokenid != USD) switch (tokenPriceTrusted(tokenid, USD)) {
                // to usd directly
                case (?priceUsd) {
                    Vector.add<LatestTokenRow>(rez, ((tokenid, USD), symbol # "/USD", priceUsd.price));
                };
                case (null)();
            };

        };

        Vector.toArray(rez);
    };
    ///
    type LatestWalletTokens = {
        latest : [LatestExtendedToken];
        ticks : [LatestWalletTokenTicks];
    };
    type LatestWalletTokenTicks = {
        from_id : TokenId;
        to_id : TokenId;
        t6h : [Float];
    };

    private func add_token_6h_price_arr(ticks : Vector.Vector<LatestWalletTokenTicks>, from_id : TokenId, to_id : TokenId) : () {
        let last : Nat = Vector.size(ticks_1h) - 1;

        let ?tpa = tokenPriceArray(from_id, to_id, last, 6, 28) else return;
        let icptz : LatestWalletTokenTicks = {
            from_id;
            to_id;
            t6h = tpa;
        };

        Vector.add(ticks, icptz);
    };

    public query func get_latest_wallet_tokens() : async LatestWalletTokens {
        let ticks = Vector.new<LatestWalletTokenTicks>();

        // Add ICP to USD
        add_token_6h_price_arr(ticks, ICP, USD);
        add_token_6h_price_arr(ticks, BTC, USD);
        add_token_6h_price_arr(ticks, ETH, USD);

        label tloop for ((token, tokenid) in Vector.items(tokens)) {
            if (tokenid == USD or tokenid == ICP or tokenid == BTC or tokenid == ETH or tokenid == XDR or token.deleted == true) continue tloop;
            add_token_6h_price_arr(ticks, tokenid, ICP);
        };

        {
            latest = get_latest_extended_internal();
            ticks = Vector.toArray(ticks);
        };
    };
    ///

    type LatestExtendedRate = {
        to_token : TokenId;
        symbol : Text;
        rate : Float;
        volume : Float;
        depth2 : Float;
        depth8 : Float;
        depth50 : Float;
    };

    type LatestExtendedToken = {
        id : TokenId;
        config : TokenConfig;
        last : ?LatestExtendedTokenTickItem;
        rates : [LatestExtendedRate];
    };

    type LatestExtendedTokenTickItem = {
        fee : Nat;
        circulating_supply : Nat;
        total_supply : Nat;
        treasury : Nat;
        other_treasuries : [(TokenId, Nat)];
        total_locked : Nat;
        dissolving_1d : Nat;
        dissolving_30d : Nat;
        dissolving_1y : Nat;
    };

    private func get_latest_extended_internal() : [LatestExtendedToken] {

        let alltokens = Vector.new<LatestExtendedToken>();

        let ?Icp2Usd = tokenPriceTrusted(ICP, USD) else Debug.trap("ICP2USD rate not available");

        label tloop for ((token, tokenid) in Vector.items(tokens)) {
            let rez = Vector.new<LatestExtendedRate>();

            let symbol = token.symbol;
            if (tokenid == USD) continue tloop; // skip USD
            if (tokenid != ICP) switch (tokenPrice(tokenid, ICP)) {
                case (?priceIcp) {
                    if (tokenid != XDR) Vector.add<LatestExtendedRate>(
                        rez,
                        {
                            to_token = ICP;
                            symbol = symbol # "/ICP";
                            rate = priceIcp.price;
                            volume = priceIcp.volume / Icp2Usd.price;
                            depth2 = priceIcp.buydepth2 * priceIcp.price;
                            depth8 = priceIcp.buydepth8 * priceIcp.price;
                            depth50 = priceIcp.buydepth50 * priceIcp.price;
                        },
                    );
                    Vector.add<LatestExtendedRate>(
                        rez,
                        {
                            to_token = USD;
                            symbol = symbol # "/USD";
                            rate = priceIcp.price * Icp2Usd.price;
                            volume = priceIcp.volume;
                            depth2 = priceIcp.buydepth2 * priceIcp.price * Icp2Usd.price;
                            depth8 = priceIcp.buydepth8 * priceIcp.price * Icp2Usd.price;
                            depth50 = priceIcp.buydepth50 * priceIcp.price * Icp2Usd.price;
                        },
                    );
                };
                case (null)();
            };

            if (tokenid != USD) switch (tokenPriceTrusted(tokenid, USD)) {
                case (?priceUsd) {
                    Vector.add<LatestExtendedRate>(
                        rez,
                        {
                            to_token = USD;
                            symbol = symbol # "/USD";
                            rate = priceUsd.price;
                            volume = priceUsd.volume;
                            depth2 = priceUsd.buydepth2 * priceUsd.price;
                            depth8 = priceUsd.buydepth8 * priceUsd.price;
                            depth50 = priceUsd.buydepth50 * priceUsd.price;
                        },
                    );
                };
                case (null)();
            };

            let last : ?LatestExtendedTokenTickItem = switch (findLastTokenTick(tokenid)) {
                case (null) null;
                case (?la) {

                    switch (la.locking) {
                        case (null) {
                            ?{
                                fee = la.fee;
                                circulating_supply = la.circulating_supply;
                                total_supply = la.total_supply;
                                total_locked = 0;
                                other_treasuries = [];
                                treasury = 0;
                                dissolving_1d = 0;
                                dissolving_30d = 0;
                                dissolving_1y = 0;
                            };
                        };
                        case (?locking) {
                            var dissolving_1d : Nat = 0;
                            var dissolving_30d : Nat = 0;
                            var dissolving_1y : Nat = 0;
                            for (idx in locking.dissolving.keys()) {
                                if (idx <= 1) dissolving_1d += locking.dissolving[idx];
                                if (idx <= 30) dissolving_30d += locking.dissolving[idx];
                                if (idx <= 365) dissolving_1y += locking.dissolving[idx];
                            };
                            ?{
                                fee = la.fee;
                                circulating_supply = la.total_supply - locking.treasury - locking.total_locked;
                                total_supply = la.total_supply;

                                total_locked = locking.total_locked;
                                other_treasuries = locking.other_treasuries;
                                treasury = locking.treasury;
                                dissolving_1d;
                                dissolving_30d;
                                dissolving_1y;
                            };

                        };
                    };

                };
            };

            Vector.add<LatestExtendedToken>(
                alltokens,
                {
                    id = tokenid;
                    config = token;
                    last;
                    rates = Vector.toArray(rez);
                },
            );
        };

        Vector.toArray(alltokens);
    };

    /// Get the latest extended token information and exchange rates against USD and ICP
    public query func get_latest_extended() : async [LatestExtendedToken] {
        get_latest_extended_internal();
    };

    // XRC
    let exchange_rate_canister : XRC.Self = actor ("uf6dk-hyaaa-aaaaq-qaaaq-cai");

    /// Collects and processes exchange rate data for pairs using the XRC service
    private func xrc_collect<system>(
        pairid : PairId,
        {
            quote_asset : XRC.Asset;
            base_asset : XRC.Asset;
        },
    ) : async () {

        Cycles.add<system>(1_000_000_000);

        let resp = await exchange_rate_canister.get_exchange_rate({
            timestamp = null;
            quote_asset;
            base_asset;
        });

        switch (resp) {
            case (#Ok(r)) {
                let price : Float = Float.fromInt(Nat64.toNat(r.rate)) / 10 ** Float.fromInt(Nat32.toNat(r.metadata.decimals));

                let volume = Option.get(last_oracle_value(base_asset.symbol # "/" # quote_asset.symbol # "-V24"), 0 : Float);

                let t : TickLast = (
                    pairid,
                    price,
                    price,
                    volume,
                    [0, 0, 0, 0, 0, 0, 0, 0],
                    [0, 0, 0, 0, 0, 0, 0, 0],
                );
                put_tick(ticks_5m, (Int.abs(Time.now()) - Int.abs(first_tick)) / (1000000000 * 60 * 5), stripDepth(t));
                put_tick(ticks_1h, (Int.abs(Time.now()) - Int.abs(first_tick)) / (1000000000 * 60 * 60), t);
                put_tick(ticks_1d, (Int.abs(Time.now()) - Int.abs(first_tick)) / (1000000000 * 60 * 60 * 24), t);

            };
            case (#Err(e)) {
                logErr("collecting XRC" # base_asset.symbol # "/" # quote_asset.symbol # " " # debug_show (e), Error.reject("Couldn't get rate"));
            };
        };
    };

    // Start timer for collecting XRC data
    // Each pair can be retrieved every 60 seconds
    ignore Timer.recurringTimer<system>(
        #seconds 60,
        func() : async () {
            label pairs for ((pair, pairid) in Vector.items(pair_config)) {
                if (pair.deleted == true) continue pairs;
                switch (pair.config) {
                    case (#xrc(xrc_pairs)) {
                        await xrc_collect(pairid, xrc_pairs);
                    };
                    case (_) continue pairs;
                };
            };
        },
    );

    // public type Master = actor {
    //     get_config : shared query () -> async {
    //         tokens : [TokenConfig];
    //         pairs : [PairConfig];
    //     };
    //     get_pairs : shared query (Frame, [Nat], ?Time.Time, ?Time.Time) -> async GetPairsResult;
    //     get_tokens : shared query ([Nat], ?Time.Time, ?Time.Time) -> async GetTokensResult;
    // };

    // private func sync_master_internal(from_master : Principal) : async () {
    //     let master = actor (Principal.toText(from_master)) : Master;

    //     let cfg = await master.get_config();
    //     Vector.clear(tokens);
    //     Vector.clear(pair_config);
    //     Vector.addFromIter(tokens, cfg.tokens.vals());
    //     Vector.addFromIter(pair_config, cfg.pairs.vals());

    //     // import tokens
    //     label token_loop for ((token, tokenid) in Vector.items(tokens)) {

    //     };

    //     // import pairs
    //     label pair_loop for ((pair, pairid) in Vector.items(pair_config)) {
    //         let from_time = first_tick;
    //         let frame : Frame = #t1d;
    //         let resp = await master.get_pairs(frame, [pairid], ?from_time, null);
    //         switch (resp) {
    //             case (#ok({ data })) {
    //                 import_pair(frame, from_time, pairid, data[0], #overwrite);
    //             };
    //             case (_)();
    //         };

    //     };

    // };

    // public shared ({ caller }) func sync_master_pair(from_master : Principal, pairid : PairId) : async () {
    //     assert (caller == adminPrincipal);

    //     let master = actor (Principal.toText(from_master)) : Master;

    //     let cfg = await master.get_config();

    //     Vector.clear(tokens);
    //     Vector.clear(pair_config);

    //     Vector.addFromIter(tokens, cfg.tokens.vals());
    //     Vector.addFromIter(pair_config, cfg.pairs.vals());
    //     let from_time = first_tick;
    //     let frame : Frame = #t1d;
    //     let resp = await master.get_pairs(frame, [pairid], ?from_time, null);
    //     switch (resp) {
    //         case (#ok({ data })) {
    //             import_pair(frame, from_time, pairid, data[0], #overwrite);
    //         };
    //         case (_) Debug.trap("Cound't get pair from master");
    //     };
    // };

    // public shared ({ caller }) func sync_master(from_master : Principal) : async () {
    //     assert (caller == adminPrincipal);
    //     try {
    //         await sync_master_internal(from_master);
    //     } catch (e) {
    //         logErr("master sync err " # Principal.toText(from_master), e);
    //     };
    // };

};
