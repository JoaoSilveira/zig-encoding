const std = @import("std");

pub fn hexString(comptime string: [:0]const u8) [string.len >> 1]u8 {
    comptime {
        if (string.len & 1 != 0) @compileError("Hex string should have even length");

        var slice: [string.len >> 1]u8 = undefined;
        for (slice) |*byte, index| {
            const double = index << 1;
            const n1 = std.fmt.charToDigit(string[double], 16) catch @compileError("Invalid Hex string");
            const n2 = std.fmt.charToDigit(string[double + 1], 16) catch @compileError("Invalid Hex string");

            byte.* = (n1 << 4) | n2;
        }

        return slice;
    }
}
