const std = @import("std");
const unicode = @import("../unicode.zig");

const Codepoint = unicode.Codepoint;

pub const ascii_max = 0x80;

pub fn encoder(cp: Codepoint, writer: anytype) !void {
    if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;
    if (cp >= ascii_max) return error.UnmappedCodepoint;

    try writer.writeByte(@truncate(u8, cp));
}

pub fn decoder(reader: anytype) !Codepoint {
    const b = try reader.readByte();
    if (b >= ascii_max) return error.InvalidByte;

    return b;
}

test "Ascii encoder" {
    var buffer: [0x80]u8 = undefined;
    var stream = std.io.fixedBufferStream(buffer[0..]);
    var writer = stream.writer();

    var cp: Codepoint = 0;
    while (cp < 0x80) : (cp += 1) {
        encoder(cp, writer) catch std.debug.panic("{} expected, but failed", .{cp});
    }

    for (buffer) |c, i| {
        std.testing.expect(c == i);
    }

    stream.seekTo(0) catch unreachable;

    std.testing.expectError(error.UnmappedCodepoint, encoder(0x80, writer));
    std.testing.expectError(error.UnmappedCodepoint, encoder(0xA34E, writer));
    std.testing.expectError(error.UnmappedCodepoint, encoder(0x81, writer));
    std.testing.expectError(error.InvalidCodepointValue, encoder(unicode.codepoint_max + 1, writer));
}

test "Ascii decoder" {
    var buffer: [256]u8 = undefined;
    for (buffer) |*c, i| {
        c.* = @truncate(u8, i);
    }

    var stream = std.io.fixedBufferStream(buffer[0..]);
    var reader = stream.reader();

    for (buffer[0..0x80]) |_, i| {
        const ans = decoder(reader) catch std.debug.panic("{} expected, but failed", .{i});

        std.testing.expect(ans == i);
    }

    for (buffer[0x80..]) |_| {
        std.testing.expectError(error.InvalidByte, decoder(reader));
    }
}
