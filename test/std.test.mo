import {clean_std} "../src/std";
import Debug "mo:base/Debug";
import {test} "mo:test";





test("Single", func() {
    let (mean, std) = clean_std([1.3]);
    assert(mean == 1.3);

});

test("Two", func() {
    let (mean, std) = clean_std([1.0,2.0]);
    assert(mean == 1.5);
});

test("Three", func() {
    let (mean, std) = clean_std([1,2,3]);
    assert(mean == 2);
});



test("Multiple with outliers", func() {

    let (mean, std) = clean_std([4.12, 4.11, 4.05, 4.45]);
    assert(mean < 4.13);
    assert(mean > 4.05);

});