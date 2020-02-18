usingnamespace @import("error.zig");
usingnamespace @import("unicode.zig");
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Decodes a single codepoint from the slice
pub fn decode(comptime Endianness: std.builtin.Endian, slice: []const u16) Utf16DecodeError!u32 {
    if (slice.len == 0) return error.DecodeEmptySlice;
    var native: [2]u16 = undefined;
    const toNative = std.mem.toNative;

    native[0] = toNative(u16, slice[0], Endianness);
    if (isSurrogate(native[0])) {
        if (slice.len == 1) return error.UnexpectedSequenceEnd;
        native[1] = toNative(u16, slice[1], Endianness);

        if (isLowSurrogate(native[0])) return error.WrongSurrogateOrder;
        if (!isLowSurrogate(native[1])) return error.ExpectedLowSurrogate;

        return ((@as(u32, native[0] - 0xD800) << 10) | (native[1] - 0xDC00)) + 0x10000;
    }

    const codepoint = @as(u32, native[0]);
    if (isSurrogate(codepoint)) return error.DecodeSurrogate;

    return codepoint;
}

/// Decodes a single codepoint from a little endian slice
pub inline fn decodeLe(slice: []const u16) !u32 {
    return decode(.Little, slice);
}

/// Decodes a single codepoint from a big endian slice
pub inline fn decodeBe(slice: []const u16) !u32 {
    return decode(.Big, slice);
}

/// Decodes a single codepoint from the slice without security checks
pub fn decodeUnsafe(comptime Endianness: std.builtin.Endian, slice: []const u16) u32 {
    const toNative = std.mem.toNative;
    var native: u16 = toNative(u16, slice[0], Endianness);

    if (isSurrogate(native)) {
        return ((@as(u32, native - 0xD800) << 10) | (toNative(u16, slice[1], Endianness) - 0xDC00)) + 0x10000;
    }

    return native;
}

/// Decodes a single codepoint from a little endian slice without security checks
pub inline fn decodeUnsafeLe(slice: []const u16) u32 {
    return decodeUnsafe(.Little, slice);
}

/// Decodes a single codepoint from a big endian slice without security checks
pub inline fn decodeUnsafeBe(slice: []const u16) u32 {
    return decodeUnsafe(.Big, slice);
}

/// Encodes a single codepoint in Utf16
pub fn encode(comptime Endianness: std.builtin.Endian, codepoint: u32, slice: []u16) EncodeError!u2 {
    if (isSurrogate(codepoint)) return error.EncodingSurrogate;
    if (codepoint > codepoint_max) return InvalidCodepointValue;
    const nativeTo = std.mem.nativeTo;

    if (isLargeCodepoint(codepoint)) {
        if (slice.len < 2) return error.InsufficientSpace;

        const cp = codepoint - 0x10000;

        slice[0] = nativeTo(u16, surrogate_min + (cp >> 10), Endianness);
        slice[1] = nativeTo(u16, (high_surrogate_max + 1) + (cp & 0x3FF), Endianness);

        return 2;
    }

    if (slice.len == 0) return error.InsufficientSpace;

    slice[0] = nativeTo(u16, @truncate(u16, codepoint), Endianness);
    return 1;
}

/// Encodes a single codepoint in Utf16Le
pub inline fn encodeLe(slice: []const u16, length: ?*u2) !u32 {
    return encode(.Little, slice, length);
}

/// Encodes a single codepoint in Utf16Be
pub inline fn encodeBe(slice: []const u16, length: ?*u2) !u32 {
    return encode(.Big, slice, length);
}

/// Encodes a single codepoint in Utf16 without security checks
pub fn encodeUnsafe(comptime Endianness: std.builtin.Endian, codepoint: u32, slice: []u16) u2 {
    const nativeTo = std.mem.nativeTo;

    if (isLargeCodepoint(codepoint)) {
        const cp = codepoint - 0x10000;

        slice[0] = nativeTo(u16, surrogate_min + (cp >> 10), Endianness);
        slice[1] = nativeTo(u16, (high_surrogate_max + 1) + (cp & 0x3FF), Endianness);

        return 2;
    }

    slice[0] = nativeTo(u16, @truncate(u16, codepoint), Endianness);
    return 1;
}

/// Encodes a single codepoint in Utf16Le without security checks
pub inline fn encodeUnsafeLe(slice: []const u16, length: ?*u2) u32 {
    return encodeUnsafe(.Little, slice, length);
}

/// Encodes a single codepoint in Utf16Be without security checks
pub inline fn encodeUnsafeBe(slice: []const u16, length: ?*u2) u32 {
    return encodeUnsafe(.Big, slice, length);
}

/// Validates an Utf16 slice
pub fn validateSlice(comptime Endianness: std.builtin.Endian, slice: []const u16) bool {
    var index: usize = 0;

    while (index < slice.len) {
        _ = decode(Endianness, slice[index..]) catch return false;
        
        index += 1 + @boolToInt(isSurrogate(slice[index]));
    }

    return true;
}

/// Validates an Utf16Le slice
pub inline fn ValidateSliceLe(slice: []const u16) bool {
    return validateSlice(.Little, slice);
}

/// Validates an Utf16Be slice
pub inline fn validateSliceBe(slice: []const u16) bool {
    return validateSlice(.Big, slice);
}

/// Iterates through a Utf16 slice
pub fn Iterator(comptime Endianness: std.builtin.Endian) type {
    return struct {
        const Self = @This();

        slice: []const u16,
        index: usize,

        /// initializes the iterator checking if the slice is valid
        pub fn init(slice: []const u16) ValidateSequenceError!Self {
            if (validateSlice(Endianness, slice)) return error.InvalidSequence;

            return initUnchecked(slice);
        }

        /// Gets the next codepoint in the slice
        pub fn nextCodepoint(self: *Self) ?u32 {
            if (self.index >= self.slice.len) return null;

            const cp = decode(Endianness, self.slice[self.index..]) catch unreachable;

            self.index += 1 + @boolToInt(isSurrogate(self.slice[self.index]));
            return cp;
        }

        /// gets the next codepoint's slice
        pub fn nextSlice(self: *Self) !?[]const u16 {
            if (self.index >= self.slice.len) return null;

            _ = decode(Endianness, self.slice[index..]) catch unreachable;

            const len = 1 + @boolToInt(isSurrogate(self.slice[self.index]));
            self.index += len;

            return self.slice[self.index - len .. self.index];
        }

        /// Resets the iteration to the beginning
        pub fn reset(self: *Iterator) void {
            self.index = 0;
        }
    };
}

/// Iterates through a Utf16Le slice
pub const LeIterator = Iterator(.Little);

/// Iterates through a Utf16Be slice
pub const BeIterator = Iterator(.Big);

/// Iterates through a Utf16 slice without security checks
pub fn IteratorUnsafe(comptime Endianness: std.builtin.Endian) type {
    return struct {
        const Self = @This();

        slice: []const u16,
        index: usize,

        /// initializes the iterator
        pub fn initUnchecked(slice: []const u16) Self {
            return .{
                .slice = slice,
                .index = 0,
            };
        }

        /// Gets the next codepoint in the slice
        pub fn nextCodepoint(self: *Self) ?u32 {
            if (self.index >= self.slice.len) return null;

            const cp = decodeUnsafe(Endianness, self.slice[self.index..]);

            self.index += 1 + @boolToInt(isSurrogate(self.slice[self.index]));
            return cp;
        }

        /// gets the next codepoint's slice
        pub fn nextSlice(self: *Self) !?[]const u16 {
            if (self.index >= self.slice.len) return null;

            _ = decodeUnsafe(Endianness, self.slice[index..]);

            const len = 1 + @boolToInt(isSurrogate(self.slice[self.index]));
            self.index += len;

            return self.slice[self.index - len .. self.index];
        }

        /// Resets the iteration to the beginning
        pub fn reset(self: *Iterator) void {
            self.index = 0;
        }
    };
}

test "Surrogates" {
    expect(isSurrogate(0xD900));
    expect(!isSurrogate(0xD100));
    expect(isHighSurrogate(0xD900));
    expect(!isHighSurrogate(0xD100));
    expect(isLowSurrogate(0xDF00));
    expect(!isLowSurrogate(0xD100));
}
