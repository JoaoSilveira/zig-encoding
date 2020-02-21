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
        const EncodingType = encoding.Encoding(encoding.CommonEncodeError, DecodeError);

        /// Errors that can happen while decoding
        ///
        /// > **remarks**: Read sequence as an UTF-16 encoded word sequence of a codepoint
        pub const DecodeError = encoding.CommonDecodeError || unicode.CodepointError || error{
            /// When the low surrogate appears first
            WrongSurrogateOrder,

            /// Expected low surrogate but there was none
            ExpectedLowSurrogate,

            /// The slice have an odd number of bytes
            BrokenByteSlice,
        };

        encoding: EncodingType,

        /// Initializes the UTF-16 encoding
        pub fn init() Self {
            return .{
                .encoding = .{
                    .encodeSingleFn = encode,
                    .decodeSingleFn = decode,
                },
            };
        }

        /// Encodes a single codepoint in Utf16
        pub fn encode(enc: *EncodingType, codepoint: Codepoint, slice: []u8) encoding.CommonEncodeError!u3 {
            if (unicode.isSurrogate(codepoint)) return error.EncodingSurrogate;
            if (codepoint > unicode.codepoint_max) return error.InvalidCodepointValue;
            if (slice.len < try codepointLength(codepoint)) return error.InsufficientSpace;

            const nativeTo = std.mem.nativeTo;
            var native_value: u16 = undefined;

            if (isLargeCodepoint(codepoint)) {
                const cp = codepoint - 0x10000;

                native_value = nativeTo(
                    u16,
                    @truncate(u16, unicode.surrogate_min + (cp >> 10)),
                    Endianness,
                );
                std.mem.copy(u8, slice, std.mem.asBytes(&native_value));

                native_value = nativeTo(
                    u16,
                    @truncate(u16, (unicode.high_surrogate_max + 1) + (cp & 0x3FF)),
                    Endianness,
                );
                std.mem.copy(u8, slice[2..], std.mem.asBytes(&native_value));
                return 4;
            }

            native_value = nativeTo(u16, @truncate(u16, codepoint), Endianness);
            std.mem.copy(u8, slice, std.mem.asBytes(&native_value));
            return 2;
        }

        /// Decodes a single codepoint from the slice
        pub fn decode(enc: *EncodingType, slice: []const u8) DecodeError!DecodeResult {
            if (slice.len == 0) return error.DecodeEmptySlice;
            if (slice.len < 2) return error.BrokenByteSlice;

            var native: [2]u16 = undefined;
            const readIntSlice = std.mem.readIntSlice;

            native[0] = readIntSlice(u16, slice, Endianness);

            if (unicode.isSurrogate(native[0])) {
                if (slice.len < 4) return error.UnexpectedSliceEnd;
                native[1] = readIntSlice(u16, slice[2..], Endianness);

                if (unicode.isLowSurrogate(native[0])) return error.WrongSurrogateOrder;
                if (unicode.isHighSurrogate(native[1])) return error.ExpectedLowSurrogate;

                return DecodeResult{
                    .codepoint = ((@as(Codepoint, native[0] - 0xD800) << 10) | (native[1] - 0xDC00)) + 0x10000,
                    .length = 4,
                };
            }

            return DecodeResult{
                .codepoint = @as(Codepoint, native[0]),
                .length = 2,
            };
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

/// Decodes a single codepoint from the slice without security checks
pub fn decodeUnsafe(comptime Endianness: std.builtin.Endian, slice: []const u16) u32 {
    const toNative = std.mem.toNative;
    var native: u16 = toNative(u16, slice[0], Endianness);

    if (unicode.isSurrogate(native)) {
        return ((@as(u32, native - 0xD800) << 10) | (toNative(u16, slice[1], Endianness) - 0xDC00)) + 0x10000;
    }

    return native;
}

/// Decodes a single codepoint from a little endian slice without security checks
pub inline fn decodeUnsafeLe(slice: []const u16) u32 {
    return decodeUnsafe(.Little, slice);
}

/// Decodes a single codepoint from a big endian slice without security checks
pub inline fn decodeUnsafeBe(slice: []const u16) u32 {
    return decodeUnsafe(.Big, slice);
}

/// Encodes a single codepoint in Utf16 without security checks
pub fn encodeUnsafe(comptime Endianness: std.builtin.Endian, codepoint: u32, slice: []u16) u2 {
    const nativeTo = std.mem.nativeTo;

    if (isLargeCodepoint(codepoint)) {
        const cp = codepoint - 0x10000;

        slice[0] = nativeTo(u16, @truncate(u16, unicode.surrogate_min + (cp >> 10)), Endianness);
        slice[1] = nativeTo(u16, @truncate(u16, (unicode.high_surrogate_max + 1) + (cp & 0x3FF)), Endianness);

        return 2;
    }

    slice[0] = nativeTo(u16, @truncate(u16, codepoint), Endianness);
    return 1;
}

/// Encodes a single codepoint in Utf16Le without security checks
pub inline fn encodeUnsafeLe(codepoint: u32, slice: []u16) u32 {
    return encodeUnsafe(.Little, codepoint, slice);
}

/// Encodes a single codepoint in Utf16Be without security checks
pub inline fn encodeUnsafeBe(codepoint: u32, slice: []u16) u32 {
    return encodeUnsafe(.Big, codepoint, slice);
}
