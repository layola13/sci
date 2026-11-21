const Binding = @import("binding_types.zig").Binding;
const bindingForBucket1 = @import("binding_lookup_1.zig").bindingForBucket1;
const bindingForBucket2 = @import("binding_lookup_2.zig").bindingForBucket2;
const bindingForBucket3 = @import("binding_lookup_3.zig").bindingForBucket3;
const bindingForBucket4 = @import("binding_lookup_4.zig").bindingForBucket4;

pub fn bindingForName(name: []const u8) ?Binding {
    return bindingForBucket1(name) orelse bindingForBucket2(name) orelse bindingForBucket3(name) orelse bindingForBucket4(name);
}
