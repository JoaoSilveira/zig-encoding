const unicode = @import("unicode.zig");
const encoding = @import("encoding.zig");
const std = @import("std");

const Codepoint = unicode.Codepoint;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const DecodeResult = encoding.DecodeResult;

pub fn Utf16Encoding(comptime Endianness: std.builtin.Endian) type {
    return struct {
        const Self = @This();

        pub const Encoder = encoding.Encoder(void, EncodeError, encode);
        pub const Decoder = encoding.Decoder(void, DecodeError, decode);
        pub const StatefulDecoder = encoding.StatefulDecoder(State, DecodeError, pushByte);
        pub const EncodeError = unicode.CodepointError || error{
            EncodingSurrogate,
            InsufficientSpace,
        };
        pub const DecodeError = unicode.CodepointError || error{
            DecodeSurrogate,
            DecodeEmptySlice,
            WrongSurrogateOrder,
            ExpectedLowSurrogate,
            BrokenByteSlice,
        };

        const State = struct {
            buffer: [4]u8 = undefined,
            index: u3 = 0,
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
            if (unicode.isSurrogate(cp)) return error.EncodingSurrogate;
            if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;
            if (slice.len < try codepointLength(cp)) return error.InsufficientSpace;

            var native_value: u16 = undefined;
            if (isLargeCodepoint(cp)) {
                const codepoint = cp - 0x10000;

                native_value = std.mem.nativeTo(
                    u16,
                    @truncate(u16, unicode.surrogate_min + (codepoint >> 10)),
                    Endianness,
                );
                std.mem.copy(u8, slice, std.mem.asBytes(&native_value));

                native_value = std.mem.nativeTo(
                    u16,
                    @truncate(u16, (unicode.high_surrogate_max + 1) + (codepoint & 0x3FF)),
                    Endianness,
                );
                std.mem.copy(u8, slice[2..], std.mem.asBytes(&native_value));
                return 4;
            }

            native_value = std.mem.nativeTo(u16, @truncate(u16, cp), Endianness);
            std.mem.copy(u8, slice, std.mem.asBytes(&native_value));
            return 2;
        }
        
        pub fn decode(self: void, slice: []const u8, cp: *Codepoint) DecodeError!u3 {
            if (slice.len == 0) return error.DecodeEmptySlice;
            if (slice.len < 2) return error.BrokenByteSlice;

            var native: [2]u16 = undefined;

            native[0] = std.mem.readIntSlice(u16, slice, Endianness);

            if (unicode.isSurrogate(native[0])) {
                if (slice.len < 4) return error.BrokenByteSlice;
                native[1] = std.mem.readIntSlice(u16, slice[2..], Endianness);

                if (unicode.isLowSurrogate(native[0])) return error.WrongSurrogateOrder;
                if (!unicode.isLowSurrogate(native[1])) return error.ExpectedLowSurrogate;

                cp.* = ((@as(Codepoint, native[0] - 0xD800) << 10) | (native[1] - 0xDC00)) + 0x10000;
                return 4;
            }

            cp.* = @as(Codepoint, native[0]);
            return 2;
        }
        
        pub fn pushByte(self: *State, byte: u8) DecodeError!?Codepoint {
            self.buffer[self.index] = byte;
            self.index += 1;

            switch (self.index) {
                2, 4 => {
                    var cp: Codepoint = undefined;

                    _ = decode(.{}, self.buffer[0..self.index], &cp) catch |e| switch (e) {
                        error.BrokenByteSlice => return null,
                        else => {
                            self.index = 0;
                            return e;
                        },
                    };

                    self.index = 0;
                    return cp;
                },
                else => return null,
            }
        }
    };
}

pub const Utf16LeEncoding = Utf16Encoding(.Little);
pub const Utf16BeEncoding = Utf16Encoding(.Big);

/// Tells if the codepoint is larger than 16 bits
pub fn isLargeCodepoint(codepoint: u32) bool {
    return codepoint > 0xFFFF;
}

/// Tells how many bytes are needed to encode the codepoint
pub fn codepointLength(codepoint: Codepoint) unicode.CodepointError!u3 {
    if (codepoint > unicode.codepoint_max) return error.InvalidCodepointValue;

    return if (isLargeCodepoint(codepoint)) 4 else 2;
}

const t = std.testing;

test "UTF16 Little Endian Decoder" {
    const hex = @import("util.zig").hexString;
    const decoder = Utf16LeEncoding.decoder();

    t.expectEqual(decoder.codepoint(hex("4800")), 'H');
    t.expectEqual(decoder.codepoint(hex("A303")), 'Σ');
    t.expectEqual(decoder.codepoint(hex("0D11")), 'ᄍ');
    t.expectEqual(decoder.codepoint(hex("3DD802DE")), '😂');
    t.expectError(error.DecodeEmptySlice, decoder.length(hex("")));
    t.expectError(error.BrokenByteSlice, decoder.length(hex("48")));
    t.expectError(error.BrokenByteSlice, decoder.length(hex("3DD802")));
    t.expectError(error.ExpectedLowSurrogate, decoder.length(hex("3DD84800")));
    t.expectError(error.WrongSurrogateOrder, decoder.length(hex("02DE3DD8")));
}

test "UTF16 Big Endian Decoder" {
    const hex = @import("util.zig").hexString;
    const decoder = Utf16BeEncoding.decoder();

    t.expectEqual(decoder.codepoint(hex("0048")), 'H');
    t.expectEqual(decoder.codepoint(hex("03A3")), 'Σ');
    t.expectEqual(decoder.codepoint(hex("110D")), 'ᄍ');
    t.expectEqual(decoder.codepoint(hex("D83DDE02")), '😂');
    t.expectError(error.DecodeEmptySlice, decoder.length(hex("")));
    t.expectError(error.BrokenByteSlice, decoder.length(hex("48")));
    t.expectError(error.BrokenByteSlice, decoder.length(hex("D83D02")));
    t.expectError(error.ExpectedLowSurrogate, decoder.length(hex("D83D0048")));
    t.expectError(error.WrongSurrogateOrder, decoder.length(hex("DE02D83D")));
}

test "UTF16 Little Endian Stateful Decoder" {
    var decoder = Utf16LeEncoding.stateful();

    t.expectEqual(decoder.pushByte(0x48), null);
    t.expectEqual(decoder.pushByte(0x00), 'H');

    t.expectEqual(decoder.pushByte(0xa3), null);
    t.expectEqual(decoder.pushByte(0x03), 'Σ');

    t.expectEqual(decoder.pushByte(0x0d), null);
    t.expectEqual(decoder.pushByte(0x11), 'ᄍ');

    t.expectEqual(decoder.pushByte(0x3d), null);
    t.expectEqual(decoder.pushByte(0xd8), null);
    t.expectEqual(decoder.pushByte(0x02), null);
    t.expectEqual(decoder.pushByte(0xde), '😂');

    t.expectEqual(decoder.pushByte(0x02), null);
    t.expectEqual(decoder.pushByte(0xde), null);
    t.expectEqual(decoder.pushByte(0x3d), null);
    t.expectError(error.WrongSurrogateOrder, decoder.pushByte(0xd8));
}

test "UTF16 Big Endian Stateful Decoder" {
    var decoder = Utf16BeEncoding.stateful();

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x48), 'H');

    t.expectEqual(decoder.pushByte(0x03), null);
    t.expectEqual(decoder.pushByte(0xa3), 'Σ');

    t.expectEqual(decoder.pushByte(0x11), null);
    t.expectEqual(decoder.pushByte(0x0d), 'ᄍ');

    t.expectEqual(decoder.pushByte(0xd8), null);
    t.expectEqual(decoder.pushByte(0x3d), null);
    t.expectEqual(decoder.pushByte(0xde), null);
    t.expectEqual(decoder.pushByte(0x02), '😂');

    t.expectEqual(decoder.pushByte(0xde), null);
    t.expectEqual(decoder.pushByte(0x02), null);
    t.expectEqual(decoder.pushByte(0xd8), null);
    t.expectError(error.WrongSurrogateOrder, decoder.pushByte(0x3d));
}

test "UTF16 Little Endian Encoder" {
    const hex = @import("util.zig").hexString;
    const encoder = Utf16LeEncoding.encoder();
    var buff: [4]u8 = undefined;
    var slice: []u8 = &buff;
    
    t.expect(std.mem.eql(
        u8,
        hex("4800"),
        try encoder.slice('H', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("A303"),
        try encoder.slice('Σ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("0D11"),
        try encoder.slice('ᄍ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("3DD802DE"),
        try encoder.slice('😂', slice),
    ));
    t.expectError(error.InsufficientSpace, encoder.encode('😂', slice[1..]));
    t.expectError(error.InvalidCodepointValue, encoder.length(0x110000));
    t.expectError(error.EncodingSurrogate, encoder.length(0xD800));
    t.expectError(error.EncodingSurrogate, encoder.length(0xDFFF));
}

test "UTF16 Big Endian Encoder" {
    const hex = @import("util.zig").hexString;
    const encoder = Utf16BeEncoding.encoder();
    var buff: [4]u8 = undefined;
    var slice: []u8 = &buff;
    
    t.expect(std.mem.eql(
        u8,
        hex("0048"),
        try encoder.slice('H', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("03A3"),
        try encoder.slice('Σ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("110D"),
        try encoder.slice('ᄍ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("D83DDE02"),
        try encoder.slice('😂', slice),
    ));
    t.expectError(error.InsufficientSpace, encoder.encode('😂', slice[1..]));
    t.expectError(error.InvalidCodepointValue, encoder.length(0x110000));
    t.expectError(error.EncodingSurrogate, encoder.length(0xD800));
    t.expectError(error.EncodingSurrogate, encoder.length(0xDFFF));
}
