const std = @import("std");
const unicode = @import("unicode.zig");

const Allocator = std.mem.Allocator;
const Codepoint = unicode.Codepoint;

/// Errors that can happen while decoding
pub const CommonDecodeError = error{
    /// There's a surrogate encoded
    DecodeSurrogate,

    /// Attempt to decode an empty slice
    DecodeEmptySlice,

    /// There are less elements in the slice than needed for the sequence
    UnexpectedSliceEnd,
};

/// Error that can happen during the encoding
pub const CommonEncodeError = unicode.CodepointError || error{
    /// Attempt to encode a surrogate
    EncodingSurrogate,

    /// Slice is too short to hold the encoded sequence
    InsufficientSpace,
};

/// Holds the result of a successfull decode
pub const DecodeResult = struct {
    codepoint: Codepoint,
    length: u3,
};

pub fn Encoding(
    comptime EncodeErrorType: type,
    comptime DecodeErrorType: type,
) type {
    return struct {
        const Self = @This();
        pub const EncodeError = EncodeErrorType;
        pub const DecodeError = DecodeErrorType;

        encodeSingleFn: fn (self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!u3,
        decodeSingleFn: fn (self: *Self, bytes: []const u8) DecodeError!DecodeResult,

        pub fn decodeSingle(self: *Self, bytes: []const u8) DecodeError!DecodeResult {
            return self.decodeSingleFn(self, bytes);
        }

        pub fn encodeSingle(self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!u3 {
            return self.encodeSinglefn(self, codepoint, bytes);
        }

        pub fn iterate(self: *Self, bytes: []const u8) Iterator {
            return Iterator.init(self, bytes);
        }

        pub fn convertToAlloc(self: *Self, target: *Self, allocator: *Allocator, bytes: []const u8) ![]u8 {
            var list = std.ArrayList.init(allocator);
            var iter = self.iterate(bytes);
            var buff: [7]u8 = undefined;

            while (try iter.nextCodepoint()) |cp| {
                var length = try target.encodeSingle(cp, buff);
                
                try list.appendSlice(buff[0..length]);
            }

            return list.toOwnedSlice();
        }

        pub fn convertToBuffer(self: *Self, target: *Self, buffer: *std.Buffer, bytes: []const u8) !void {
            var iter = self.iterate(bytes);
            var buff: [7]u8 = undefined;

            while (try iter.nextCodepoint()) |cp| {
                var length = try target.encodeSingle(cp, buff);
                
                try buffer.append(buff[0..length]);
            }
        }

        pub fn convertToSlice(self: *Self, target: *Self, slice: []u8, bytes: []const u8) !void {
            var iter = self.iterate(bytes);
            var buff: [7]u8 = undefined;
            var index: usize = 0;

            while (try iter.nextCodepoint()) |cp| {
                var length = try target.encodeSingle(cp, buff);

                if (index + length > slice.len) return error.InsufficientSpace;

                std.mem.copy(u8, slice[index..], buff[0..length]);
                index += length;
            }
        }

        pub const Iterator = struct {
            const Self = @This();

            index: usize,
            bytes: []const u8,
            encoding: *Encoding(EncodeError, DecodeError, LengthError),

            pub fn init(
                encoding: *Encoding(EncodeError, DecodeError, LengthError),
                bytes: []const u8,
            ) Self {
                return .{
                    .index = 0,
                    .bytes = bytes,
                };
            }

            pub fn nextCodepoint(self: *Self) !?Codepoint {
                if (self.index >= self.bytes) return null;

                const ans = try self.encoding.decodeSingle(self.bytes[index..]);
                self.index += ans.length;

                return ans.codepoint;
            }

            pub fn nextSlice(self: *Self) !?[]const u8 {
                if (self.index >= self.bytes) return null;

                const ans = try self.encoding.decodeSingle(self.bytes[index..]);
                self.index += ans.length;

                return self.bytes[self.index - ans.length .. self.index];
            }

            pub fn reset(self: *Self) void {
                self.index = 0;
            }
        };
    };
}
