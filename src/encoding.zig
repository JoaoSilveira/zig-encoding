const unicode = @import("unicode.zig");

const Codepoint = unicode.Codepoint;

pub fn Encoding(
    comptime EncodeError: type,
    comptime DecodeError: type,
    comptime LengthError: type,
) type {
    return struct {
        const Self = @This();

        encodeSinglefn: fn (self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!void,
        decodeSingleFn: fn (self: *Self, bytes: []const u8) DecodeError!Codepoint,
        encodeLengthFn: fn (self: *Self, codepoint: Codepoint) LengthError!usize,

        pub fn decodeSingle(self: *Self, bytes: []const u8) DecodeError!Codepoint {
            return self.decodeSingleFn(self, bytes);
        }

        pub fn encodeSingle(self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!void {
            return self.encodeSinglefn(self, codepoint, bytes);
        }

        pub fn encodeLength(self: *Self, codepoint: Codepoint) LengthError!usize {
            return self.encodeLengthFn(self, codepoint);
        }
    };
}
