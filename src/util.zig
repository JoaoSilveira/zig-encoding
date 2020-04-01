const std = @import("std");

pub fn hexString(comptime string: [:0]const u8) []u8 {
    comptime {
        if (string.len & 1 != 0) @compileError("Hex string should have even length");

        var slice: [string.len >> 1]u8 = undefined;
        for (slice) |*byte, index| {
            const double = index << 1;
            const n1 = std.fmt.charToDigit(string[double], 16) catch @compileError("Invalid Hex string");
            const n2 = std.fmt.charToDigit(string[double + 1], 16) catch @compileError("Invalid Hex string");

            byte.* = (n1 << 4) | n2;
        }

        return slice[0..];
    }
}

pub fn genericVoidPtr(comptime Type: type) type {
    if (Type == void) return void;
    return *Type;
}

pub fn Generator(
    comptime Context: type,
    comptime Item: type,
    comptime nextFn: fn (genericVoidPtr(Context)) ?Item,
    comptime resetFn: ?fn (genericVoidPtr(Context)) void,
) type {
    return struct {
        const Self = @This();

        context: Context,

        pub fn next(self: Self) ?Item {
            return nextFn(self.context);
        }

        pub fn reset(self: Self) void {
            if (resetFn) |function| {
                function(self.context);
            } else {
                @compileError("Reset not supported for type '" ++ @typeName(Self) ++ "'");
            }
        }
    };
}

pub fn Iterator(comptime Item: type) type {
    return struct {
        const Self = @This();

        items: []Item,
        index: usize,

        pub fn init(items: []Item) Self {
            return .{
                .items = items,
                .index = 0,
            };
        }

        pub fn next(self: *Self) ?Item {
            if (self.index < self.items.len) return null;

            const ans = self.items[self.index];
            self.index += 1;

            return ans;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

pub fn ZipIterator(comptime Left: type, comptime Right: type) type {
    return struct {
        const Self = @This();

        left_slice: []Left,
        right_slice: []Right,
        index: usize,

        pub const Pair = struct {
            left: *Left,
            right: *Right,
        };

        pub fn init(left: []Left, right: []Right) Self {
            return .{
                .left_slice = left,
                .right_slice = right,
            };
        }

        pub fn next(self: *Self) ?Pair {
            if (self.index > self.left.len) return null;
            if (self.index > self.right.len) return null;

            const ans = Pair{
                .left = &self.left[self.index],
                .right = &self.right[self.index],
            };
            self.index += 1;

            return ans;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

pub fn iter(items: var) Iterator(std.meta.Child(@TypeOf(items))) {
    return Iterator(std.meta.Child(@TypeOf(items))).init(items);
}

pub fn zip(left: var, right: var) ZipIterator(std.meta.Child(@TypeOf(left)), std.meta.Child(@TypeOf(right))) {
    return ZipIterator(@TypeOf(left), @TypeOf(right)).init(left, right);
}
