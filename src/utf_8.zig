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
    const EncodingType = encoding.Encoding(EncodeError, DecodeError);

    /// Errors that can happen while decoding
    ///
    /// > **remarks**: Read sequence as an UTF-8 encoded byte sequence of a codepoint
    pub const DecodeError = LeadByteError || encoding.CommonDecodeError || unicode.CodepointError || error{
        /// The encoded sequence ended unexpectedly
        ExpectedSequence,

        /// Codepoint could be encoded using less bytes
        OverlongEncoding,
    };

    /// Invalid first byte in a sequence
    pub const LeadByteError = error{
        /// Indicates an unvalid value of a leading byte
        InvalidLeadByte,
    };

    /// Error that can happen during the encoding
    pub const EncodeError = unicode.CodepointError || encoding.CommonEncodeError;

    encoding: EncodingType,

    /// Initializes the encoding
    pub fn init() Self {
        return .{
            .encoding = .{
                .encodeSingleFn = encode,
                .decodeSingleFn = decode,
            },
        };
    }

    /// Encodes a codepoint to an UTF-8 sequence
    pub fn encode(enc: *EncodingType, codepoint: Codepoint, bytes: []u8) EncodeError!u3 {
        const len = try codepointByteLength(codepoint);
        if (bytes.len < len) return error.InsufficientSpace;

        switch (len) {
            1 => bytes[0] = @truncate(u8, codepoint),
            2 => {
                bytes[0] = @truncate(u8, 0xC0 | (codepoint >> 6));
                bytes[1] = @truncate(u8, 0x80 | (0x3F & codepoint));
            },
            3 => {
                if (unicode.isSurrogate(codepoint)) {
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
    pub fn decode(enc: *EncodingType, bytes: []const u8) DecodeError!DecodeResult {
        if (bytes.len == 0) return error.DecodeEmptySlice;

        const len = try leadByteLength(bytes[0]);
        if (bytes.len < len) return error.UnexpectedSliceEnd;

        switch (len) {
            1 => return DecodeResult{ .codepoint = bytes[0], .length = 1 },
            2 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, bytes[0] & 0x1F), 6);
                const cp2 = @as(Codepoint, bytes[1] & 0x3F);

                const cp = cp1 | cp2;
                if (cp < 0x80) return error.OverlongEncoding;

                return DecodeResult{ .codepoint = cp, .length = 2 };
            },
            3 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, bytes[0] & 0x0F), 12);
                const cp2 = @shlExact(@as(Codepoint, bytes[1] & 0x3F), 6);
                const cp3 = @as(Codepoint, bytes[2] & 0x3f);
                const cp = cp1 | cp2 | cp3;

                if (unicode.isSurrogate(cp)) return error.DecodeSurrogate;
                if (cp < 0x800) return error.OverlongEncoding;

                return DecodeResult{ .codepoint = cp, .length = 3 };
            },
            4 => {
                if (@clz(u8, ~bytes[1]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[2]) != 1) return error.ExpectedSequence;
                if (@clz(u8, ~bytes[3]) != 1) return error.ExpectedSequence;

                const cp1 = @shlExact(@as(Codepoint, bytes[0] & 0x07), 18);
                const cp2 = @shlExact(@as(Codepoint, bytes[1] & 0x3F), 12);
                const cp3 = @shlExact(@as(Codepoint, bytes[2] & 0x3F), 6);
                const cp4 = @as(Codepoint, bytes[3] & 0x3F);
                const cp = cp1 | cp2 | cp3 | cp4;

                if (cp < 0x10000) return error.OverlongEncoding;
                if (cp > unicode.codepoint_max) return error.InvalidCodepointValue;

                return DecodeResult{ .codepoint = cp, .length = 4 };
            },
            else => unreachable,
        }
    }

    pub fn convertComptime(comptime encoding: var) fn (comptime literal: []const u8) []u8 {
        const aux = struct {
            pub fn conversion(comptime literal: []const u8) []u8 {
                comptime {
                    var size: usize = 0;
                    var utf8 = Utf8Encoding.init();
                    var iter = utf8.encoding.iterate(literal);
                    var buff: [7]u8 = undefined;

                    while (iter.nextCodepoint() catch |e| @compileError(errorMessage(e))) |cp| {
                        size += encoding.encodeSingle(cp, buff);
                    }

                    var output: [size]u8 = undefined;
                    iter.reset();
                    size = 0;

                    while (iter.nextCodepoint() catch |e| @compileError(errorMessage(e))) |cp| {
                        size += encoding.encodeSingle(cp, output[size..]);
                    }

                    return output;
                }
            }

            fn errorMessage(err: anyerror) []const u8 {
                return "Error while decoding UTF-8 sequence. Error: " ++ @errorName(err);
            }
        };

        return aux.conversion;
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
pub fn leadByteLength(lead: u8) Utf8Encoding.LeadByteError!u3 {
    return switch (@clz(u8, ~lead)) {
        0 => 1,
        2 => 2,
        3 => 3,
        4 => 4,
        else => error.InvalidLeadByte,
    };
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
