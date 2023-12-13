import Float "mo:base/Float";

module {
    type Mean = Float;
    type Std = Float;

    // Using standard deviation to filter outliers and then recalculating the standard deviation on the filtered data 

    public func clean_std(s: [Float]) : (Mean, Std) {

        if (s.size() == 0) {
            return (0, 0);
        };

        if (s.size() == 1) {
            return (s[0], 0);
        };

        if (s.size() == 2) {
            return ( (s[0] + s[1]) /2, Float.sqrt((s[0] + s[1]) / 2));
        };


        // Compute mean
        var sum: Float = 0;
        for ( val in s.vals() ) {
            sum += val;
        };

        let mean:Mean = sum / Float.fromInt(s.size());

        // Compute std
        var sum2: Float = 0;
        for ( val in s.vals() ) {
            sum2 += (val - mean) * (val - mean);
        };

        let std:Std = Float.sqrt(sum2 / Float.fromInt(s.size()));

        // Compute new mean without outliers
        var sum3: Float = 0;
        var count: Int = 0;
        for ( val in s.vals() ) {
            if (val > mean - 1 * std and val < mean + 1 * std) {
                sum3 += val;
                count += 1;
            };
        };

        let mean2:Mean = sum3 / Float.fromInt(count);
        
        (mean2, std)

    };
}