module {
    public type Time = Int;
    public type Volume = Nat;
    public type Self = actor {
        getPairVolumes : shared query () -> async [(Text, Volume, Volume)];
    };
};
