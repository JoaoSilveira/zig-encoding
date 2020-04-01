const unicode = @import("unicode.zig");
const encoding = @import("encoding.zig");
const std = @import("std");

const Codepoint = unicode.Codepoint;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const DecodeResult = encoding.DecodeResult;

pub fn Utf32Encoding(comptime Endianness: std.builtin.Endian) type {
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
            UnexpectedSliceEnd,
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
            if (slice.len < 4) return error.InsufficientSpace;

            var target_value: u32 = std.mem.nativeTo(u32, cp, Endianness);

            std.mem.copy(u8, slice[0..], std.mem.asBytes(&target_value));
            return 4;
        }

        pub fn decode(self: void, slice: []const u8, cp: *Codepoint) DecodeError!u3 {
            if (slice.len == 0) return error.DecodeEmptySlice;
            if (slice.len < 4) return error.UnexpectedSliceEnd;

            var native_value = std.mem.readIntSlice(u32, slice, Endianness);

            if (native_value > unicode.codepoint_max) return error.InvalidCodepointValue;
            if (unicode.isSurrogate(@truncate(Codepoint, native_value))) return error.DecodeSurrogate;

            cp.* = @truncate(Codepoint, native_value);
            return 4;
        }

        pub fn pushByte(self: *State, byte: u8) DecodeError!?Codepoint {
            self.buffer[self.index] = byte;
            self.index += 1;

            if (self.index == 4) {
                var cp: Codepoint = undefined;
                _ = decode(.{}, self.buffer[0..self.index], &cp) catch |e| {
                    self.index = 0;
                    return e;
                };

                self.index = 0;
                return cp;
            }

            return null;
        }
    };
}

pub const Utf32LeEncoding = Utf32Encoding(.Little);
pub const Utf32BeEncoding = Utf32Encoding(.Big);

const t = std.testing;

test "UTF32 Little Endian Decoder" {
    const hex = @import("util.zig").hexString;
    const decoder = Utf32LeEncoding.decoder();

    t.expectEqual(decoder.codepoint(hex("48000000")), 'H');
    t.expectEqual(decoder.codepoint(hex("A3030000")), 'Σ');
    t.expectEqual(decoder.codepoint(hex("0D110000")), 'ᄍ');
    t.expectEqual(decoder.codepoint(hex("02f60100")), '😂');
    t.expectError(error.DecodeEmptySlice, decoder.length(hex("")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("48")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("3DD8")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("3DD802")));
    t.expectError(error.InvalidCodepointValue, decoder.length(hex("00001100")));
    t.expectError(error.DecodeSurrogate, decoder.length(hex("00d80000")));
    t.expectError(error.DecodeSurrogate, decoder.length(hex("ffdf0000")));
}

test "UTF32 Big Endian Decoder" {
    const hex = @import("util.zig").hexString;
    const decoder = Utf32BeEncoding.decoder();

    t.expectEqual(decoder.codepoint(hex("00000048")), 'H');
    t.expectEqual(decoder.codepoint(hex("000003A3")), 'Σ');
    t.expectEqual(decoder.codepoint(hex("0000110D")), 'ᄍ');
    t.expectEqual(decoder.codepoint(hex("0001f602")), '😂');
    t.expectError(error.DecodeEmptySlice, decoder.length(hex("")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("48")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("3DD8")));
    t.expectError(error.UnexpectedSliceEnd, decoder.length(hex("3DD802")));
    t.expectError(error.InvalidCodepointValue, decoder.length(hex("00110000")));
    t.expectError(error.DecodeSurrogate, decoder.length(hex("0000d800")));
    t.expectError(error.DecodeSurrogate, decoder.length(hex("0000dfff")));
}

test "UTF32 Little Endian Stateful Decoder" {
    var decoder = Utf32LeEncoding.stateful();

    t.expectEqual(decoder.pushByte(0x48), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), 'H');

    t.expectEqual(decoder.pushByte(0xa3), null);
    t.expectEqual(decoder.pushByte(0x03), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), 'Σ');

    t.expectEqual(decoder.pushByte(0x0d), null);
    t.expectEqual(decoder.pushByte(0x11), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), 'ᄍ');

    t.expectEqual(decoder.pushByte(0x02), null);
    t.expectEqual(decoder.pushByte(0xf6), null);
    t.expectEqual(decoder.pushByte(0x01), null);
    t.expectEqual(decoder.pushByte(0x00), '😂');

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x11), null);
    t.expectError(error.InvalidCodepointValue, decoder.pushByte(0x00));
}

test "UTF32 Big Endian Stateful Decoder" {
    var decoder = Utf32BeEncoding.stateful();

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x48), 'H');

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x03), null);
    t.expectEqual(decoder.pushByte(0xa3), 'Σ');

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x11), null);
    t.expectEqual(decoder.pushByte(0x0d), 'ᄍ');

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x01), null);
    t.expectEqual(decoder.pushByte(0xf6), null);
    t.expectEqual(decoder.pushByte(0x02), '😂');

    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectEqual(decoder.pushByte(0x11), null);
    t.expectEqual(decoder.pushByte(0x00), null);
    t.expectError(error.InvalidCodepointValue, decoder.pushByte(0x00));
}

test "UTF32 Little Endian Encoder" {
    const hex = @import("util.zig").hexString;
    const encoder = Utf32LeEncoding.encoder();
    var buff: [4]u8 = undefined;
    var slice: []u8 = &buff;
    
    t.expect(std.mem.eql(
        u8,
        hex("48000000"),
        try encoder.slice('H', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("A3030000"),
        try encoder.slice('Σ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("0D110000"),
        try encoder.slice('ᄍ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("02f60100"),
        try encoder.slice('😂', slice),
    ));
    t.expectError(error.InsufficientSpace, encoder.encode('😂', slice[1..]));
    t.expectError(error.InvalidCodepointValue, encoder.length(0x110000));
    t.expectError(error.EncodingSurrogate, encoder.length(0xD800));
    t.expectError(error.EncodingSurrogate, encoder.length(0xDFFF));
}

test "UTF32 Big Endian Encoder" {
    const hex = @import("util.zig").hexString;
    const encoder = Utf32BeEncoding.encoder();
    var buff: [4]u8 = undefined;
    var slice: []u8 = &buff;
    
    t.expect(std.mem.eql(
        u8,
        hex("00000048"),
        try encoder.slice('H', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("000003A3"),
        try encoder.slice('Σ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("0000110D"),
        try encoder.slice('ᄍ', slice),
    ));
    t.expect(std.mem.eql(
        u8,
        hex("0001f602"),
        try encoder.slice('😂', slice),
    ));
    t.expectError(error.InsufficientSpace, encoder.encode('😂', slice[1..]));
    t.expectError(error.InvalidCodepointValue, encoder.length(0x110000));
    t.expectError(error.EncodingSurrogate, encoder.length(0xD800));
    t.expectError(error.EncodingSurrogate, encoder.length(0xDFFF));
}
