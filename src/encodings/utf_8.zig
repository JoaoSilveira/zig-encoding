const std = @import("std");
const unicode = @import("../unicode.zig");

const Codepoint = unicode.Codepoint;

pub fn encoder(cp: Codepoint, writer: anytype) !void {
    const len = try codepointByteLength(cp);
    if (slice.len < len) return error.InsufficientSpace;

    switch (len) {
        1 => try writer.writeByte(@truncate(u8, cp)),
        2 => {
            try writer.writeByte(@truncate(u8, 0xC0 | (cp >> 6)));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & cp)));
        },
        3 => {
            if (unicode.isSurrogate(cp)) {
                return error.EncodeSurrogate;
            }

            try writer.writeByte(@truncate(u8, 0xE0 | (cp >> 12)));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & (cp >> 6))));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & cp)));
        },
        4 => {
            try writer.writeByte(@truncate(u8, 0xF0 | (cp >> 18)));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & (cp >> 12))));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & (cp >> 6))));
            try writer.writeByte(@truncate(u8, 0x80 | (0x3F & cp)));
        },
        else => unreachable,
    }
}

pub fn decoder(reader: anytype) !Codepoint {
    var slice = [4]u8{ try reader.readByte(), 0, 0, 0 };
    const len = try leadByteLength(slice[0]);

    for (slice[1..len]) |*c, i| {
        c.* = try reader.readByte();
        if (@clz(u8, ~c.*) != 1) return error.ExpectedSequence;
    }

    switch (len) {
        1 => {
            return slice[0];
        },
        2 => {
            const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x1F), 6);
            const cp2 = @as(Codepoint, slice[1] & 0x3F);

            const cp_aux = cp1 | cp2;
            if (cp_aux < 0x80) return error.OverlongEncoding;

            return cp_aux;
        },
        3 => {
            const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x0F), 12);
            const cp2 = @shlExact(@as(Codepoint, slice[1] & 0x3F), 6);
            const cp3 = @as(Codepoint, slice[2] & 0x3f);
            const cp_aux = cp1 | cp2 | cp3;

            if (unicode.isSurrogate(cp_aux)) return error.DecodeSurrogate;
            if (cp_aux < 0x800) return error.OverlongEncoding;

            return cp_aux;
        },
        4 => {
            const cp1 = @shlExact(@as(Codepoint, slice[0] & 0x07), 18);
            const cp2 = @shlExact(@as(Codepoint, slice[1] & 0x3F), 12);
            const cp3 = @shlExact(@as(Codepoint, slice[2] & 0x3F), 6);
            const cp4 = @as(Codepoint, slice[3] & 0x3F);
            const cp_aux = cp1 | cp2 | cp3 | cp4;

            if (cp_aux < 0x10000) return error.OverlongEncoding;
            if (cp_aux > unicode.codepoint_max) return error.InvalidCodepointValue;

            return cp_aux;
        },
        else => unreachable,
    }
}

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
