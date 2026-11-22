const runRosettaPartA = @import("rosetta_a.zig").runRosettaPartA;
const runRosettaPartB = @import("rosetta_b.zig").runRosettaPartB;
const runRosettaPartC = @import("rosetta_c.zig").runRosettaPartC;

test "js backend rosetta demos match expected output under node" {
    try runRosettaPartA();
    try runRosettaPartB();
    try runRosettaPartC();
}
