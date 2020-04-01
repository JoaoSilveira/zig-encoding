const std = @import("std");
const encoding = @import("encoding.zig");
const unicode = @import("unicode.zig");

const Codepoint = unicode.Codepoint;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const DecodeResult = encoding.DecodeResult;

pub const Utf8Encoding = struct {
    const Self = @This();

    pub const Encoder = encoding.Encoder(void, EncodeError, encode);
    pub const Decoder = encoding.Decoder(void, DecodeError, decode);
    pub const StatefulDecoder = encoding.StatefulDecoder(State, DecodeError, pushByte);
    pub const EncodeError = unicode.CodepointError || error{
        EncodingSurrogate,
        InsufficientSpace,
    };
    pub const DecodeError = unicode.CodepointError || error{
        InvalidLeadByte,
        DecodeSurrogate,
        DecodeEmptySlice,
        UnexpectedSliceEnd,
        ExpectedSequence,
        OverlongEncoding,
    };

    const State = struct {
        buffer: [4]u8 = undefined,
        index: u3 = 0,

        pub fn decodeBuffer(self: *State) DecodeError!Codepoint {
            var cp: Codepoint = undefined;
            self.index = 0;

            _ = try decode(.{}, self.buffer[0..], &cp);
            return cp;
        }
    };

    pub fn encoder() Encoder {
        return .{ .context = .{} };
    }

    pub fn decoder() Decoder {
        return .{ .context = .{} };
    }

    pub fn stateful() StatefulDecoder {
        return .{ .context = .{} };
    }

    pub fn encode(self: void, cp: Codepoint, slice: []u8) EncodeError!u3 {
        const len = try codepointByteLength(cp);
        if (slice.len < len) return error.InsufficientSpace;

        switch (len) {
            1 => slice[0] = @truncate(u8, cp),
            2 => {
                slice[0] = @truncate(u8, 0xC0 | (cp >> 6));
                slice[1] = @truncate(u8, 0x80 | (0x3F & cp));
            },
            3 => {
                if (unicode.isSurrogate(cp)) {
                    return error.EncodingSurrogate;
                }

                slice[0] = @truncate(u8, 0xE0 | (cp >> 12));
                slice[1] = @truncate(u8, 0x80 | (0x3F & (cp >> 6)));
                slice[2] = @truncate(u8, 0x80 | (0x3F & cp));
            },
            4 => {
                slice[0] = @truncate(u8, 0xF0 | (cp >> 18));
                slice[1] = @truncate(u8, 0x80 | (0x3F & (cp >> 12)));
                slice[2] = @truncate(u8, 0x80 | (0x3F & (cp >> 6)));
                slice[3] = @truncate(u8, 0x80 | (0x3F & cp));
            },
            else => unreachable,
        }

        return len;
    }

    pub fn decode(self: void, slice: []const u8, cp: *Codepoint) DecodeError!u3 {
        if (slice.len == 0) return error.DecodeEmptySlice;

        const len = try leadByteLength(slice[0]);
        if (slice.len < len) return error.UnexpectedSliceEnd;

        switch (len) {
            1 => {
                cp.* = slice[0];
                return 1;
            },
            2 => {
                if (@clz(u8, ~slice[1]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x1F), 6);
                const cp2 = @as(Codepoint, slice[1] & 0x3F);

                const cp_aux = cp1 | cp2;
                if (cp_aux < 0x80) return error.OverlongEncoding;

                cp.* = cp_aux;
                return 2;
            },
            3 => {
                if (@clz(u8, ~slice[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~slice[2]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x0F), 12);
                const cp2 = @shlExact(@as(Codepoint, slice[1] & 0x3F), 6);
                const cp3 = @as(Codepoint, slice[2] & 0x3f);
                const cp_aux = cp1 | cp2 | cp3;

                if (unicode.isSurrogate(cp_aux)) return error.DecodeSurrogate;
                if (cp_aux < 0x800) return error.OverlongEncoding;

                cp.* = cp_aux;
                return 3;
            },
            4 => {
                if (@clz(u8, ~slice[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~slice[2]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~slice[3]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x07), 18);
                const cp2 = @shlExact(@as(Codepoint, slice[1] & 0x3F), 12);
                const cp3 = @shlExact(@as(Codepoint, slice[2] & 0x3F), 6);
                const cp4 = @as(Codepoint, slice[3] & 0x3F);
                const cp_aux = cp1 | cp2 | cp3 | cp4;

                if (cp_aux < 0x10000) return error.OverlongEncoding;
                if (cp_aux > unicode.codepoint_max) return error.InvalidCodepointValue;

                cp.* = cp_aux;
                return 4;
            },
            else => unreachable,
        }
    }

    pub fn pushByte(self: *State, byte: u8) DecodeError!?Codepoint {
        errdefer self.index = 0;
        self.buffer[self.index] = byte;

        const len = try leadByteLength(self.buffer[0]);
        self.index += 1;

        return if (self.index == len) try self.decodeBuffer() else null;
    }
};

/// Compute how many bytes are necessary to encode the codepoint
pub fn codepointByteLength(codepoint: u32) unicode.CodepointError!u3 {
    if (codepoint < 0x80) return 1;
    if (codepoint < 0x800) return 2;
    if (codepoint < 0x10000) return 3;
    if (codepoint <= unicode.codepoint_max) return 4;

    return error.InvalidCodepointValue;
}

/// Compute the sequence length by the first byte
pub fn leadByteLength(lead: u8) error{InvalidLeadByte}!u3 {
    return switch (@clz(u8, ~lead)) {
        0 => 1,
        2 => 2,
        3 => 3,
        4 => 4,
        else => error.InvalidLeadByte,
    };
}

const t = std.testing;

test "UTF8 Decoder" {
    const hex = @import("util.zig").hexString;
    const decoder = Utf8Encoding.decoder();

    t.expectEqual(decoder.codepoint("H"), 'H');
    t.expectEqual(decoder.codepoint("Σ"), 'Σ');
    t.expectEqual(decoder.codepoint("ᄍ"), 'ᄍ');
    t.expectEqual(decoder.codepoint("😂"), '😂');
    t.expectError(error.DecodeEmptySlice, decoder.length(hex("")));
    t.expectError(error.InvalidLeadByte, decoder.length(hex("ff")));
    t.expectError(error.ExpectedSequence, decoder.length(hex("ce2e")));
    t.expectError(error.ExpectedSequence, decoder.length(hex("cec3")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("ce")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("e1")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("e184")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("f0")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("f09f")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("f09f98")));
    t.expectError(error.OverlongEncoding, decoder.length(hex("c0b3")));
    t.expectError(error.InvalidCodepointValue, decoder.length(hex("f7bfbfbf")));
    t.expectError(error.DecodeSurrogate, decoder.length(hex("eda080")));
}

test "UTF8 Stateful Decoder" {
    var decoder = Utf8Encoding.stateful();

    t.expectEqual(decoder.pushByte('H'), 'H');

    t.expectEqual(decoder.pushByte(0xce), null);
    t.expectEqual(decoder.pushByte(0xa3), 'Σ');

    t.expectEqual(decoder.pushByte(0xe1), null);
    t.expectEqual(decoder.pushByte(0x84), null);
    t.expectEqual(decoder.pushByte(0x8d), 'ᄍ');

    t.expectEqual(decoder.pushByte(0xf0), null);
    t.expectEqual(decoder.pushByte(0x9f), null);
    t.expectEqual(decoder.pushByte(0x98), null);
    t.expectEqual(decoder.pushByte(0x82), '😂');

    t.expectEqual(decoder.pushByte(0xf0), null);
    t.expectEqual(decoder.pushByte(0x9f), null);
    t.expectEqual(decoder.pushByte(0x18), null);
    t.expectError(error.ExpectedSequence, decoder.pushByte(0x82));
}

test "UTF8 Encoder" {
    const encoder = Utf8Encoding.encoder();
    var buff: [4]u8 = undefined;
    var slice: []u8 = &buff;

    t.expect(std.mem.eql(
        u8,
        "H",
        try encoder.slice('H', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        "Σ",
        try encoder.slice('Σ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        "ᄍ",
        try encoder.slice('ᄍ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        "😂",
        try encoder.slice('😂', slice),
    ));
    t.expectError(error.InsufficientSpace, encoder.encode('😂', slice[1..]));
    t.expectError(error.InvalidCodepointValue, encoder.length(0x110000));
    t.expectError(error.EncodingSurrogate, encoder.length(0xD800));
    t.expectError(error.EncodingSurrogate, encoder.length(0xDFFF));
}
