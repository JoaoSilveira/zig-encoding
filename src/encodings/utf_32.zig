const std = @import("std");
const unicode = @import("../unicode.zig");

const Codepoint = unicode.Codepoint;

pub fn Utf32(comptime endian: std.builtin.Endian) type {
    return struct {
        pub fn encoder(cp: Codepoint, writer: anytype) !void {
            if (unicode.isSurrogate(cp)) return error.EncodeSurrogate;
            if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;

            if (comptime endian == .Little) {
                try writer.writeIntLittle(u32, cp);
            } else {
                try writer.writeIntBig(u32, cp);
            }
        }

        pub fn decoder(reader: anytype) !Codepoint {
            const cp = if (comptime endian == .Little)
                try reader.readIntLittle(u32)
            else
                try reader.readIntBig(u32);

            if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;
            if (unicode.isSurrogate(@truncate(Codepoint, cp))) return error.DecodeSurrogate;

            return @truncate(Codepoint, cp);
        }
    };
}

pub const utf_32le = Utf32(.Little);
pub const utf_32be = Utf32(.Big);

fn testEncoder(comptime endian: std.builtin.Endian) void {
    comptime const encoder = Utf32(endian).encoder;
    var buffer: [4]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    var writer = stream.writer();
    var reader = stream.reader();

    var cp: Codepoint = 0;
    while (true) {
        switch (cp) {
            0...unicode.surrogate_min - 1,
            unicode.surrogate_max + 1...unicode.codepoint_max,
            => {
                encoder(cp, writer) catch std.debug.panic("{} expected, but failed.", .{cp});

                stream.pos = 0;
                const encoded = reader.readInt(u32, endian) catch unreachable;
                stream.pos = 0;

                std.testing.expectEqual(encoded, cp);
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
    comptime const decoder = Utf32(endian).decoder;
    var buffer: [4]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    var writer = stream.writer();
    var reader = stream.reader();

    var cp: Codepoint = 0;
    while (true) {
        switch (cp) {
            0...unicode.surrogate_min - 1,
            unicode.surrogate_max + 1...unicode.codepoint_max,
            => {
                writer.writeInt(u32, cp, endian) catch unreachable;
                stream.pos = 0;

                const ans = decoder(reader) catch std.debug.panic("{} expected, but failed.", .{cp});
                std.testing.expectEqual(ans, cp);
                stream.pos = 0;
            },
            unicode.surrogate_min...unicode.surrogate_max => {
                writer.writeInt(u32, cp, endian) catch unreachable;
                stream.pos = 0;

                std.testing.expectError(error.DecodeSurrogate, decoder(reader));
                stream.pos = 0;
            },
            unicode.codepoint_max + 1...std.math.maxInt(Codepoint) => {
                writer.writeInt(u32, cp, endian) catch unreachable;
                stream.pos = 0;

                std.testing.expectError(error.InvalidCodepointValue, decoder(reader));
                stream.pos = 0;
            },
        }

        cp = std.math.add(Codepoint, cp, 1) catch break;
    }
}

test "UTF-32 encoder" {
    testEncoder(.Little);
    testEncoder(.Big);
}

test "UTF-32 decoder" {
    testDecoder(.Little);
    testDecoder(.Big);
}
