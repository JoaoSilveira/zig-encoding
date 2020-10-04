const std = @import("std");
pub const unicode = @import("unicode.zig");
pub const ascii = @import("encodings/ascii.zig");
pub const utf_8 = @import("encodings/utf_8.zig");
pub const utf_16 = @import("encodings/utf_16.zig");
pub const utf_32 = @import("encodings/utf_32.zig");

pub const Codepoint = unicode.Codepoint;

pub const EncoderFunction = fn (cp: Codepoint, writer: anytype) anyerror!void;
pub const DecoderFunction = fn (reader: anytype) anyerror!Codepoint;

pub fn convert(
    reader: anytype,
    writer: anytype,
    decoder: DecoderFunction,
    encoder: EncoderFunction,
) !void {
    while (true) {
        const cp = decoder(reader) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        try encoder(cp, writer);
    }
}

pub fn String(
    comptime decoderFn: DecoderFunction,
) type {
    return struct {
        pub const Decoder = decoderFn;
    };
}

test "" {
    std.meta.refAllDecls(@This());
}