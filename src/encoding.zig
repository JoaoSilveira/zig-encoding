const std = @import("std");
const root = @import("root");
const unicode = @import("unicode.zig");
const utf8 = @import("utf_8.zig");

pub const DefaultEncoding = if (@hasDecl(root, "DefaultEncoding")) root.DefaultEncoding else utf8.Utf8Encoding;
const Allocator = std.mem.Allocator;
const Codepoint = unicode.Codepoint;
const ArrayList = std.ArrayList;
const trait = std.meta.trait;

pub fn literal(comptime string: [:0]const u8) [:0]const u8 {
    if (DefaultEncoding == utf8.Utf8Encoding) return string;
}

pub fn TextInStream(comptime Decoder: type) type {
    return struct {
        const Self = @This();
    };
}

pub fn Iterator(comptime DecoderType: type) type {
    return struct {
        const Self = @This();

        index: usize,
        bytes: []const u8,
        decoder: DecoderType,

        pub fn init(
            decoder: DecoderType,
            bytes: []const u8,
        ) Self {
            return .{
                .index = 0,
                .bytes = bytes,
                .decoder = decoder,
            };
        }

        pub fn nextCodepoint(self: *Self) !?Codepoint {
            if (self.index >= self.bytes.len) return null;

            var cp: Codepoint = undefined;
            self.index += try self.decoder.decode(self.bytes[self.index..], &cp);

            return cp;
        }

        pub fn nextSlice(self: *Self) !?[]const u8 {
            if (self.index >= self.bytes.len) return null;

            var cp: Codepoint = undefined;
            const len = try self.decoder.decode(self.bytes[self.index..], &cp);
            self.index += len;

            return self.bytes[self.index - len .. self.index];
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }
    };
}

pub const FallbackStrategy = union(enum) {
    const Self = @This();

    Ignore,
    RaiseError,
    Character: Codepoint,
    Fn: fn (Codepoint) Codepoint,
    Method: MethodData,

    pub const MethodData = struct {
        const Data = @This();

        pointer: usize,
        method: fn (usize, Codepoint) Codepoint,
    };

    pub fn fromChar(char: Codepoint) Self {
        return .{ .Character = char };
    }

    pub fn fromFn(function: fn (Codepoint) Codepoint) Self {
        return .{ .Fn = function };
    }

    pub fn fromMethod(context: var, comptime method: fn (@TypeOf(context), Codepoint) Codepoint) Self {
        const Context = @TypeOf(context);

        if (comptime !std.meta.trait.isSingleItemPtr(Context)) @compileError("'context' must be a pointer");
        if (comptime !std.meta.trait.isContainer(std.meta.Child(Context))) @compileError("'context' must point to a container type");

        const AuxClosure = struct {
            pub fn call(ptr_value: usize, cp: Codepoint) Codepoint {
                var ptr = @intToPtr(Context, ptr_value);

                return method(ptr, cp);
            }
        };

        return .{
            .Method = .{
                .pointer = @ptrToInt(context),
                .method = AuxClosure.call,
            },
        };
    }

    pub fn resolve(self: Self, missing: Codepoint) error{EmptyFallback}!Codepoint {
        return switch (self) {
            .Ignore, .RaiseError => error.EmptyFallback,
            .Character => |c| c,
            .Fn => |f| f(missing),
            .Method => |d| d.method(d.pointer, missing),
        };
    }
};

fn contextArgType(comptime Context: type) type {
    if (Context == void) return void;
    return *Context;
}

pub fn Encoder(
    comptime Context: type,
    comptime EncodeErrorType: type,
    comptime encodeFn: fn (contextArgType(Context), Codepoint, []u8) EncodeErrorType!u3,
) type {
    return struct {
        const Self = @This();
        pub const Context = Context;
        pub const EncodeError = EncodeErrorType;

        context: Context,

        pub fn encode(self: *Self, cp: Codepoint, out: []u8) EncodeError!u3 {
            if (comptime Context == void) {
                return encodeFn(.{}, cp, out);
            } else {
                return encodeFn(&self.context, cp, out);
            }
        }

        pub fn length(self: *Self, cp: Codepoint) EncodeError!u3 {
            var buffer: [4]u8 = undefined;
            return self.encode(cp, buffer[0..]);
        }

        pub fn slice(self: *Self, cp: Codepoint, buffer: []u8) EncodeError![]u8 {
            const len = try self.encode(cp, buffer[0..]);
            return buffer[0..len];
        }
    };
}

pub fn Decoder(
    comptime Context: type,
    comptime DecodeErrorType: type,
    comptime decodeFn: fn (contextArgType(Context), []const u8, *Codepoint) DecodeErrorType!u3,
) type {
    return struct {
        const Self = @This();
        pub const Context = Context;
        pub const DecodeError = DecodeErrorType;

        context: Context,

        pub fn decode(self: *Self, slice: []const u8, cp: *Codepoint) DecodeError!u3 {
            if (comptime Context == void) {
                return decodeFn(.{}, slice, cp);
            } else {
                return decodeFn(&self.context, slice, cp);
            }
        }

        pub fn codepoint(self: *Self, slice: []const u8) DecodeError!Codepoint {
            var cp: Codepoint = undefined;
            if (0 == try self.decode(slice, &cp)) return 0;

            return cp;
        }

        pub fn length(self: *Self, slice: []const u8) DecodeError!u3 {
            var cp: Codepoint = undefined;
            return self.decode(slice, &cp);
        }
    };
}

pub fn StatefulDecoder(
    comptime Context: type,
    comptime DecodeErrorType: type,
    comptime pushByteFn: fn (contextArgType(Context), u8) DecodeErrorType!?Codepoint,
) type {
    return struct {
        const Self = @This();
        pub const Context = Context;
        pub const DecodeError = DecodeErrorType;

        context: Context,

        pub fn pushByte(self: *Self, byte: u8) DecodeError!?Codepoint {
            if (comptime Context == void) {
                return pushByteFn(.{}, byte);
            } else {
                return pushByteFn(&self.context, byte);
            }
        }
    };
}

// pub fn Encoding(
//     comptime EncoderType: type,
//     comptime DecoderType: type,
//     comptime StatefulDecoderType: type,
// ) type {
//     const AuxClosure = struct {
//         const meta = std.meta;
//         const trait = meta.trait;
//         const FnArg = std.builtin.TypeInfo.FnArg;

//         pub fn validateMethod(comptime Context: type, comptime method: [:0]const u8, comptime Signature: type) bool {
//             var decl = meta.declarationInfo(Context, method);

//             if (decl.data != .Fn) {
//                 @compileError("Declaration '" ++ method ++ "' of type '" ++ @typeName(Context) ++ "' is not a function");
//             }

//             var method = @typeInfo(decl.data.Fn.fn_type).Fn;

//             switch (@typeInfo(Signature)) {
//                 .Fn => |function| {
//                     const bool_test = method.calling_convention != function.calling_convention or
//                         method.is_generic != function.is_generic or
//                         method.is_var_args != function.is_var_args or
//                         method.return_type != function.return_type or
//                         !std.mem.eql(FnArg, method.args, function.args);

//                     return !bool_test;
//                 },
//                 else => @compileError("'Signature' must be a fn"),
//             }
//         }
//     };

//     return struct {
//         const Self = @This();

//         encoder: EncoderType,
//         decoder: DecoderType,
//         stateful: StatefulDecoderType,

//         pub const Iterator = struct {
//             const Self = @This();

//             index: usize,
//             bytes: []const u8,
//             decoder: *DecoderType,

//             pub fn init(
//                 decoder: *DecoderType,
//                 bytes: []const u8,
//             ) Self {
//                 return .{
//                     .index = 0,
//                     .bytes = bytes,
//                     .decoder = decoder,
//                 };
//             }

//             pub fn nextCodepoint(self: *Self) !?Codepoint {
//                 if (self.index >= self.bytes) return null;

//                 var cp: Codepoint = undefined;
//                 self.index += try self.decoder.decode(self.bytes[self.index..], &cp);

//                 return cp;
//             }

//             pub fn nextSlice(self: *Self) !?[]const u8 {
//                 if (self.index >= self.bytes) return null;

//                 var cp: Codepoint = undefined;
//                 const len = try self.encoding.decodeSingle(self.bytes[self.index..], &cp);
//                 self.index += len;

//                 return self.bytes[self.index - len .. self.index];
//             }

//             pub fn reset(self: *Self) void {
//                 self.index = 0;
//             }
//         };
//     };
// }

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

// pub fn Encoding(
//     comptime EncodeErrorType: type,
//     comptime DecodeErrorType: type,
// ) type {
//     return struct {
//         const Self = @This();
//         pub const EncodeError = EncodeErrorType;
//         pub const DecodeError = DecodeErrorType;

//         encodeSingleFn: fn (self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!u3,
//         decodeSingleFn: fn (self: *Self, bytes: []const u8) DecodeError!DecodeResult,

//         pub fn decodeSingle(self: *Self, bytes: []const u8) DecodeError!DecodeResult {
//             return self.decodeSingleFn(self, bytes);
//         }

//         pub fn encodeSingle(self: *Self, codepoint: Codepoint, bytes: []u8) EncodeError!u3 {
//             return self.encodeSinglefn(self, codepoint, bytes);
//         }

//         pub fn iterate(self: *Self, bytes: []const u8) Iterator {
//             return Iterator.init(self, bytes);
//         }

//         pub fn convertToAlloc(self: *Self, target: *Self, allocator: *Allocator, bytes: []const u8) ![]u8 {
//             var list = std.ArrayList.init(allocator);
//             var iter = self.iterate(bytes);
//             var buff: [7]u8 = undefined;

//             while (try iter.nextCodepoint()) |cp| {
//                 var length = try target.encodeSingle(cp, buff);

//                 try list.appendSlice(buff[0..length]);
//             }

//             return list.toOwnedSlice();
//         }

//         pub fn convertToBuffer(self: *Self, target: *Self, buffer: *std.Buffer, bytes: []const u8) !void {
//             var iter = self.iterate(bytes);
//             var buff: [7]u8 = undefined;

//             while (try iter.nextCodepoint()) |cp| {
//                 var length = try target.encodeSingle(cp, buff);

//                 try buffer.append(buff[0..length]);
//             }
//         }

//         pub fn convertToSlice(self: *Self, target: *Self, slice: []u8, bytes: []const u8) !void {
//             var iter = self.iterate(bytes);
//             var buff: [7]u8 = undefined;
//             var index: usize = 0;

//             while (try iter.nextCodepoint()) |cp| {
//                 var length = try target.encodeSingle(cp, buff);

//                 if (index + length > slice.len) return error.InsufficientSpace;

//                 std.mem.copy(u8, slice[index..], buff[0..length]);
//                 index += length;
//             }
//         }

//         pub const Iterator = struct {
//             const Self = @This();

//             index: usize,
//             bytes: []const u8,
//             encoding: *Encoding(EncodeError, DecodeError, LengthError),

//             pub fn init(
//                 encoding: *Encoding(EncodeError, DecodeError, LengthError),
//                 bytes: []const u8,
//             ) Self {
//                 return .{
//                     .index = 0,
//                     .bytes = bytes,
//                 };
//             }

//             pub fn nextCodepoint(self: *Self) !?Codepoint {
//                 if (self.index >= self.bytes) return null;

//                 const ans = try self.encoding.decodeSingle(self.bytes[index..]);
//                 self.index += ans.length;

//                 return ans.codepoint;
//             }

//             pub fn nextSlice(self: *Self) !?[]const u8 {
//                 if (self.index >= self.bytes) return null;

//                 const ans = try self.encoding.decodeSingle(self.bytes[index..]);
//                 self.index += ans.length;

//                 return self.bytes[self.index - ans.length .. self.index];
//             }

//             pub fn reset(self: *Self) void {
//                 self.index = 0;
//             }
//         };
//     };
// }
