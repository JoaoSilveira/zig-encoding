const std = @import("std");
const unicode = @import("../unicode.zig");

const Codepoint = unicode.Codepoint;

pub fn Utf16(comptime endian: std.builtin.Endian) type {
    return struct {
        const utf16_offset = 0x10000;

        pub fn encoder(cp: Codepoint, writer: anytype) !void {
            if (unicode.isSurrogate(cp)) return error.EncodeSurrogate;
            if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;

            if (isLargeCodepoint(cp)) {
                const codepoint = cp - utf16_offset;

                const left = unicode.surrogate_min + (codepoint >> 10);
                const right = unicode.low_surrogate_min + (codepoint & 0x3FF);
                if (comptime endian == .Little) {
                    try writer.writeIntLittle(u16, @truncate(u16, left));
                    try writer.writeIntLittle(u16, @truncate(u16, right));
                } else {
                    try writer.writeIntBig(u16, @truncate(u16, left));
                    try writer.writeIntBig(u16, @truncate(u16, right));
                }
            } else {
                if (comptime endian == .Little) {
                    try writer.writeIntLittle(u16, @truncate(u16, cp));
                } else {
                    try writer.writeIntBig(u16, @truncate(u16, cp));
                }
            }
        }

        pub fn decoder(reader: anytype) !Codepoint {
            const left = if (comptime endian == .Little)
                try reader.readIntLittle(u16)
            else
                try reader.readIntBig(u16);

            if (unicode.isSurrogate(left)) {
                const right = if (comptime endian == .Little)
                    try reader.readIntLittle(u16)
                else
                    try reader.readIntBig(u16);

                if (unicode.isLowSurrogate(left)) return error.WrongSurrogateOrder;
                if (!unicode.isLowSurrogate(right)) return error.ExpectedLowSurrogate;

                return utf16_offset + ((@as(Codepoint, left - unicode.surrogate_min) << 10) |
                    (right - unicode.low_surrogate_min));
            }

            return left;
        }

        /// Tells if the codepoint is larger than 16 bits
        pub fn isLargeCodepoint(codepoint: u32) bool {
            return codepoint > 0xFFFF;
        }

        /// Tells how many bytes are needed to encode the codepoint
        pub fn codepointLength(codepoint: Codepoint) unicode.CodepointError!u3 {
            if (codepoint > unicode.codepoint_max) return error.InvalidCodepointValue;

            return if (isLargeCodepoint(codepoint)) 4 else 2;
        }
    };
}

pub const utf_16le = Utf16(.Little);
pub const utf_16be = Utf16(.Big);

fn testEncoder(comptime endian: std.builtin.Endian) void {
    comptime const encoder = Utf16(endian).encoder;
    var buffer: [4]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    var writer = stream.writer();
    var reader = stream.reader();

    var cp: Codepoint = 0;
    while (true) {
        switch (cp) {
            0...unicode.surrogate_min - 1,
            unicode.surrogate_max + 1...0xFFFF,
            => {
                encoder(cp, writer) catch std.debug.panic("{} expected, but failed.", .{cp});

                stream.pos = 0;
                const encoded = reader.readInt(u16, endian) catch unreachable;
                stream.pos = 0;

                std.testing.expectEqual(cp, encoded);
            },
            0x10000...unicode.codepoint_max => {
                encoder(cp, writer) catch std.debug.panic("{} expected, but failed.", .{cp});

                stream.pos = 0;
                const left = reader.readInt(u16, endian) catch unreachable;
                const right = reader.readInt(u16, endian) catch unreachable;
                stream.pos = 0;

                // the `-0x10000` is there to eliminate the 21st bit
                // high 10 bits (high surrogate)
                std.testing.expectEqual(((cp - 0x10000) >> 10) + unicode.surrogate_min, left);

                // low 10 bits (low surrogate)
                std.testing.expectEqual(((cp - 0x10000) & 0x3FF) + unicode.low_surrogate_min, right);
            },
            unicode.surrogate_min...unicode.surrogate_max => {
                std.testing.expectError(error.EncodeSurrogate, encoder(cp, writer));
            },
            unicode.codepoint_max + 1...std.math.maxInt(Codepoint) => {
                std.testing.expectError(error.InvalidCodepointValue, encoder(cp, writer));
            },
        }

        cp = std.math.add(Codepoint, cp, 1) catch break;
    }
}

fn testDecoder(comptime endian: std.builtin.Endian) void {
    comptime const decoder = Utf16(endian).decoder;
    var buffer: [4]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    var writer = stream.writer();
    var reader = stream.reader();

    var cp: Codepoint = 0;
    while (true) {
        switch (cp) {
            0...unicode.surrogate_min - 1,
            unicode.surrogate_max + 1...0xFFFF,
            => {
                writer.writeInt(u16, @truncate(u16, cp), endian) catch unreachable;
                stream.pos = 0;

                const ans = decoder(reader) catch std.debug.panic("{} expected, but failed.", .{cp});
                std.testing.expectEqual(ans, cp);
                stream.pos = 0;
            },
            0x10000...unicode.codepoint_max => {
                writer.writeInt(u16, @truncate(u16, ((cp - 0x10000) >> 10) + unicode.surrogate_min), endian) catch unreachable;
                writer.writeInt(u16, @truncate(u16, ((cp - 0x10000) & 0x3FF) + unicode.low_surrogate_min), endian) catch unreachable;
                stream.pos = 0;

                const ans = decoder(reader) catch std.debug.panic("{} expected, but failed.", .{cp});
                std.testing.expectEqual(ans, cp);
                stream.pos = 0;
            },
            unicode.surrogate_min...unicode.surrogate_max => {
                // skip, this test is covered by `0x10000...unicode.codepoint_max` and `unicode.codepoint_max + 1...std.math.maxInt(Codepoint)`
                cp = unicode.surrogate_max;
            },
            unicode.codepoint_max + 1...std.math.maxInt(Codepoint) => {
                // in this test `cp - 0x10000` will result in 11 bits
                // because of this the high surrogate equation will result into a low surrogate
                writer.writeInt(u16, @truncate(u16, ((cp - 0x10000) >> 10) + unicode.surrogate_min), endian) catch unreachable;
                writer.writeInt(u16, @truncate(u16, ((cp - 0x10000) & 0x3FF) + unicode.low_surrogate_min), endian) catch unreachable;
                stream.pos = 0;

                std.testing.expectError(error.WrongSurrogateOrder, decoder(reader));
                stream.pos = 0;
            },
        }

        cp = std.math.add(Codepoint, cp, 1) catch break;
    }
}

test "UTF-16 Encoder" {
    testEncoder(.Little);
    testEncoder(.Big);
}

test "UTF-16 Decoder" {
    testDecoder(.Little);
    testDecoder(.Big);
}
