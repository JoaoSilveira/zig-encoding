usingnamespace @import("error.zig");
usingnamespace @import("unicode.zig");

const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

pub const Utf8Encoding = struct {
    const Self = @This();

    /// Errors that can happen while decoding
    /// Remarks: Read sequence as an UTF-8 encoded byte sequence of a codepoint
    pub const DecodeError = LeadByteError || DecodeError || CodepointError || error{
        /// There are enough bytes in the slice but the sequence
        /// ended unexpectedly
        ExpectedSequence,
    };

    /// Invalid first byte in a sequence
    pub const LeadByteError = error{
        /// Indicates an unvalid value of a leading byte
        InvalidLeadByte,
    };

    /// Error that can happen during the encoding
    pub const EncodeError = CodepointError || EncodeError;

    encoding: Encoding(EncodeError, DecodeError, CodepointError),

    /// Initializes the encoding
    pub fn init() Self {
        return .{
            .encoding = .{
                .encodeSingleFn = encode,
                .decodeSingleFn = decode,
                .encodeLengthFn = encodeLength,
            },
        };
    }

    /// Encodes a codepoint to an UTF-8 sequence
    pub fn encode(self: *Self, codepoint: u32, bytes: []u8) EncodeError!u3 {
        const len = try codepointByteLength(codepoint);
        if (bytes.len < len) return error.InsufficientSpace;

        switch (len) {
            1 => bytes[0] = @truncate(u8, codepoint),
            2 => {
                bytes[0] = @truncate(u8, 0xC0 | (codepoint >> 6));
                bytes[1] = @truncate(u8, 0x80 | (0x3F & codepoint));
            },
            3 => {
                if (isSurrogate(codepoint)) {
                    return error.EncodingSurrogate;
                }

                bytes[0] = @truncate(u8, 0xE0 | (codepoint >> 12));
                bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
                bytes[2] = @truncate(u8, 0x80 | (0x3F & codepoint));
            },
            4 => {
                bytes[0] = @truncate(u8, 0xF0 | (codepoint >> 18));
                bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 12)));
                bytes[2] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
                bytes[3] = @truncate(u8, 0x80 | (0x3F & codepoint));
            },
            else => unreachable,
        }

        return len;
    }

    /// Decodes an UTF-8 encoded sequence to a codepoint value
    pub fn decode(self: *Self, bytes: []const u8) DecodeError!u32 {
        if (bytes.len == 0) return error.DecodeEmptySlice;

        const len = try leadByteLength(bytes[0]);
        if (bytes.len < len) return error.UnexpectedSequenceEnd;

        switch (len) {
            1 => return bytes[0],
            2 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(u32, bytes[0] & 0x1F), 6);
                const cp2 = @as(u32, bytes[1] & 0x3F);

                const cp = cp1 | cp2;
                if (cp < 0x80) return error.OverlongEncoding;

                return cp;
            },
            3 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(u32, bytes[0] & 0x0F), 12);
                const cp2 = @shlExact(@as(u32, bytes[1] & 0x3F), 6);
                const cp3 = @as(u32, bytes[2] & 0x3f);
                const cp = cp1 | cp2 | cp3;

                if (isSurrogate(cp)) return error.DecodeSurrogate;
                if (cp < 0x800) return error.OverlongEncoding;

                return cp;
            },
            4 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[3]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(u32, bytes[0] & 0x07), 18);
                const cp2 = @shlExact(@as(u32, bytes[1] & 0x3F), 12);
                const cp3 = @shlExact(@as(u32, bytes[2] & 0x3F), 6);
                const cp4 = @as(u32, bytes[3] & 0x3F);
                const cp = cp1 | cp2 | cp3 | cp4;

                if (cp < 0x10000) return error.OverlongEncoding;
                if (cp > codepoint_max) return error.InvalidCodepointValue;

                return cp;
            },
            else => unreachable,
        }
    }

    pub fn encodeLength(self: *Self, codepoint: Codepoint) CodepointError!Codepoint {
        return codepointByteLength(codepoint);
    }
};

/// Compute how many bytes are necessary to encode the codepoint
pub fn codepointByteLength(codepoint: u32) CodepointError!u3 {
    if (codepoint < 0x80) return 1;
    if (codepoint < 0x800) return 2;
    if (codepoint < 0x10000) return 3;
    if (codepoint <= codepoint_max) return 4;

    return error.InvalidCodepointValue;
}

/// Compute the sequence length by the first byte
pub fn leadByteLength(lead: u8) Utf8LeadByteError!u3 {
    return switch (@clz(u8, ~lead)) {
        0 => 1,
        2 => 2,
        3 => 3,
        4 => 4,
        else => error.InvalidLeadByte,
    };
}

/// Validades a UTF-8 slice
pub fn validateSlice(bytes: []const u8) bool {
    if (bytes.len == 0) return false;

    var base_index: usize = 0;
    while (base_index < bytes.len) {
        const len = leadByteLength(bytes[base_index]) catch return false;
        if (base_index + len > bytes.len) return false;

        _ = decode(bytes[base_index..]) catch return false;
        base_index += len;
    }
    return true;
}

/// Decodes an UTF-8 encoded sequence to a codepoint value
pub fn decode(bytes: []const u8) Utf8DecodeError!u32 {
    if (bytes.len == 0) return error.DecodeEmptySlice;

    const len = try leadByteLength(bytes[0]);
    if (bytes.len < len) return error.UnexpectedSequenceEnd;

    switch (len) {
        1 => return bytes[0],
        2 => {
            if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;

            const cp1 = @shlExact(@as(u32, bytes[0] & 0x1F), 6);
            const cp2 = @as(u32, bytes[1] & 0x3F);

            const cp = cp1 | cp2;
            if (cp < 0x80) return error.OverlongEncoding;

            return cp;
        },
        3 => {
            if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
            if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;

            const cp1 = @shlExact(@as(u32, bytes[0] & 0x0F), 12);
            const cp2 = @shlExact(@as(u32, bytes[1] & 0x3F), 6);
            const cp3 = @as(u32, bytes[2] & 0x3f);
            const cp = cp1 | cp2 | cp3;

            if (isSurrogate(cp)) return error.DecodeSurrogate;
            if (cp < 0x800) return error.OverlongEncoding;

            return cp;
        },
        4 => {
            if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
            if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;
            if (@clz(u8, ~bytes[3]) != 1) return error.ExpectedSequence;

            const cp1 = @shlExact(@as(u32, bytes[0] & 0x07), 18);
            const cp2 = @shlExact(@as(u32, bytes[1] & 0x3F), 12);
            const cp3 = @shlExact(@as(u32, bytes[2] & 0x3F), 6);
            const cp4 = @as(u32, bytes[3] & 0x3F);
            const cp = cp1 | cp2 | cp3 | cp4;

            if (cp < 0x10000) return error.OverlongEncoding;
            if (cp > codepoint_max) return error.InvalidCodepointValue;

            return cp;
        },
        else => unreachable,
    }
}

/// Decodes an UTF-8 encoded sequence to a codepoint without doing any checks
pub fn decodeUnsafe(bytes: []const u8) u32 {
    const len = leadByteLength(bytes[0]) catch unreachable;

    return switch (len) {
        1 => bytes[0],
        2 => @shlExact(@as(u32, bytes[0] & 0x1F), 6) | @as(u32, bytes[1] & 0x3F),
        3 => @shlExact(@as(u32, bytes[0] & 0x0F), 12) | @shlExact(@as(u32, bytes[1] & 0x3F), 6) | @as(u32, bytes[2] & 0x3f),
        4 => @shlExact(@as(u32, bytes[0] & 0x07), 18) | @shlExact(@as(u32, bytes[1] & 0x3F), 12) | @shlExact(@as(u32, bytes[2] & 0x3F), 6) | @as(u32, bytes[3] & 0x3F),
        else => unreachable,
    };
}

/// Encodes a codepoint to an UTF-8 sequence
pub fn encode(codepoint: u32, bytes: []u8) Utf8EncodeError!u3 {
    const len = try codepointByteLength(codepoint);
    if (bytes.len < len) return error.InsufficientSpace;

    switch (len) {
        1 => bytes[0] = @truncate(u8, codepoint),
        2 => {
            bytes[0] = @truncate(u8, 0xC0 | (codepoint >> 6));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        3 => {
            if (isSurrogate(codepoint)) {
                return error.EncodingSurrogate;
            }

            bytes[0] = @truncate(u8, 0xE0 | (codepoint >> 12));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
            bytes[2] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        4 => {
            bytes[0] = @truncate(u8, 0xF0 | (codepoint >> 18));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 12)));
            bytes[2] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
            bytes[3] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        else => unreachable,
    }

    return len;
}

/// Encodes a codepoint to an UTF-8 sequence without doing any checks
pub fn encodeUnsafe(codepoint: u32, bytes: []u8) u3 {
    const len = codepointByteLength(codepoint) catch unreachable;

    switch (len) {
        1 => bytes[0] = @truncate(u8, codepoint),
        2 => {
            bytes[0] = @truncate(u8, 0xC0 | (codepoint >> 6));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        3 => {
            bytes[0] = @truncate(u8, 0xE0 | (codepoint >> 12));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
            bytes[2] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        4 => {
            bytes[0] = @truncate(u8, 0xF0 | (codepoint >> 18));
            bytes[1] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 12)));
            bytes[2] = @truncate(u8, 0x80 | (0x3F & (codepoint >> 6)));
            bytes[3] = @truncate(u8, 0x80 | (0x3F & codepoint));
        },
        else => unreachable,
    }

    return len;
}

/// An UTF-8 iterator. Can iterate by slices or codepoints
pub const Iterator = struct {
    /// UTF-8 byte sequence
    bytes: []const u8,

    /// current index in the byte sequence
    index: usize,

    /// Initializes an Iterator validating the sequence.
    pub fn init(bytes: []const u8) ValidateSequenceError!Iterator {
        if (!validateSlice(bytes)) return error.InvalidSequence;

        return initUnchecked(bytes);
    }

    /// Initializes an Iterator without validating
    pub fn initUnchecked(bytes: []const u8) Iterator {
        return .{
            .bytes = bytes,
            .index = 0,
        };
    }

    /// Returns the next codepoint if any
    pub fn nextCodepoint(self: *Iterator) !?u32 {
        if (self.index >= self.bytes.len) return null;

        const len = try leadByteLength(self.bytes[self.index]);
        self.index += len;

        return try decode(self.bytes[self.index - len ..]);
    }

    /// Returns the next slice if any
    pub fn nextSlice(self: *Iterator) !?[]const u8 {
        if (self.index >= self.bytes.len) return null;

        _ = try decode(self.bytes[self.index..]);

        const len = try leadByteLength(self.bytes[self.index]);
        self.index += len;

        return self.bytes[self.index - len .. self.index];
    }

    /// Resets the iteration to the beginning
    pub fn reset(self: *Iterator) void {
        self.index = 0;
    }
};

test "Iterator" {
    var iter = Iterator.initUnchecked("Hello");

    expectEqual(try iter.nextCodepoint().?, 'H');
    expectEqual(try iter.nextCodepoint().?, 'e');
    expectEqual(try iter.nextCodepoint().?, 'l');
    expectEqual(try iter.nextCodepoint().?, 'l');
    expectEqual(try iter.nextCodepoint().?, 'o');
    expectEqual(try iter.nextCodepoint(), null);

    iter.reset();

    expect(std.mem.eql(u8, try iter.nextSlice().?, "H"));
    expect(std.mem.eql(u8, try iter.nextSlice().?, "e"));
    expect(std.mem.eql(u8, try iter.nextSlice().?, "l"));
    expect(std.mem.eql(u8, try iter.nextSlice().?, "l"));
    expect(std.mem.eql(u8, try iter.nextSlice().?, "o"));
    expect(try iter.nextSlice() == null);

    expectError(error.InvalidUtf8Sequence, Iterator.init("hel\xadlo"));
}

test "Encoding" {
    const encode = encodeSecure;
    var arr: [4]u8 = undefined;

    expectEqual(try encode(0x40, arr[0..]), 1);
    expect(std.mem.eql(u8, arr[0..1], "@"));

    expectEqual(try encode(0x03A9, arr[0..]), 2);
    expect(std.mem.eql(u8, arr[0..2], "Ω"));

    expectEqual(try encode(0x2211, arr[0..]), 3);
    expect(std.mem.eql(u8, arr[0..3], "∑"));

    expectEqual(try encode(0x1F914, arr[0..]), 4);
    expect(std.mem.eql(u8, arr[0..4], "🤔"));

    expectError(error.EncodingSurrogate, encode(0xD922, arr[0..]));
    expectError(error.InvalidCodepointValue, encode(0xCADE1A, arr[0..]));
    expectError(error.InsufficientSpace, encode(0x1F914, arr[3..]));
}

test "Decoding" {
    const decode = decodeSecure;

    expectEqual(try decode("@"), 0x40);
    expectEqual(try decode("Ω"), 0x03A9);
    expectEqual(try decode("∑"), 0x2211);
    expectEqual(try decode("🤔"), 0x1F914);

    expectError(error.InvalidLeadByte, decode([_]u8{0xF8}));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xCE, 0x08 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xC0, 0xA0 }));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xEE, 0x88, 0x08 }));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xEE, 0x08, 0x88 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xE0, 0x80, 0xA0 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xE0, 0x87, 0xA9 }));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xF6, 0x08, 0x88, 0x88 }));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xF6, 0x88, 0x08, 0x88 }));
    expectError(error.Utf8ExpectedSequence, decode([_]u8{ 0xF6, 0x88, 0x88, 0x08 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xF0, 0x80, 0x80, 0xA0 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xF0, 0x80, 0x8C, 0x80 }));
    expectError(error.OverlongEncoding, decode([_]u8{ 0xF0, 0x89, 0x80, 0xA0 }));
    expectError(error.InvalidCodepointValue, decode([_]u8{ 0xF5, 0x89, 0x80, 0xA0 }));
    expectError(error.DecodeEmptySlice, decode([_]u8{}));
    expectError(error.UnexpectedSequenceEnd, decode([_]u8{ 0xE2, 0x88 }));
}

test "Codepoint Length" {
    const cbl = codepointByteLength;

    expectEqual(try cbl(0x24), @as(u3, 1)); // $
    expectEqual(try cbl(0x3A9), @as(u3, 2)); // Ω
    expectEqual(try cbl(0x2211), @as(u3, 3)); // ∑
    expectEqual(try cbl(0x1F914), @as(u3, 4)); // 🤔
    expectError(error.InvalidCodepointValue, cbl(0xCADE1A));
}

test "Lead byte length" {
    const lbl = leadByteLength;

    expectEqual(try lbl(0x24), @as(u3, 1));
    expectEqual(try lbl(0xD1), @as(u3, 2));
    expectEqual(try lbl(0xE4), @as(u3, 3));
    expectEqual(try lbl(0xF7), @as(u3, 4));
    expectError(error.InvalidLeadByte, lbl(0xF8));
}
