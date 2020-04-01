const unicode = @import("unicode.zig");
const encoding = @import("encoding.zig");
const std = @import("std");

const Codepoint = unicode.Codepoint;

pub const AsciiEncoding = struct {
    const Self = @This();

    pub const Encoder = encoding.Encoder(AscIiFallback, EncodeError, encode);
    pub const Decoder = encoding.Decoder(AscIiFallback, DecodeError, decode);
    pub const StatefulDecoder = encoding.StatefulDecoder(AscIiFallback, DecodeError, pushByte);
    pub const EncodeError = error{
        UnmappedCodepoint,
        InsufficientSpace,
        InvalidFallbackValue,
    };
    pub const DecodeError = error{
        InvalidByte,
        DecodeEmptySlice,
        InvalidFallbackValue,
    };

    const AscIiFallback = struct {
        strategy: encoding.FallbackStrategy,
    };

    pub fn encoder() Encoder {
        return encoderFallback(.RaiseError);
    }

    pub fn decoder() Decoder {
        return decoderFallback(.RaiseError);
    }

    pub fn stateful() StatefulDecoder {
        return statefulFallback(.RaiseError);
    }

    pub fn encoderFallback(fallback: encoding.FallbackStrategy) Encoder {
        return Encoder{ .context = .{ .strategy = fallback } };
    }

    pub fn decoderFallback(fallback: encoding.FallbackStrategy) Decoder {
        return Decoder{ .context = .{ .strategy = fallback } };
    }

    pub fn statefulFallback(fallback: encoding.FallbackStrategy) StatefulDecoder {
        return StatefulDecoder{ .context = .{ .strategy = fallback } };
    }

    pub fn encode(self: *AscIiFallback, cp: Codepoint, slice: []u8) EncodeError!u3 {
        if (slice.len == 0) return error.InsufficientSpace;

        if (cp < 128) {
            slice[0] = @truncate(u8, cp);
            return 1;
        }

        switch (self.strategy) {
            .Ignore => return 0,
            .RaiseError => return error.UnmappedCodepoint,
            else => {
                const char = self.strategy.resolve(cp) catch unreachable;

                if (char < 128) {
                    slice[0] = @truncate(u8, char);
                    return 1;
                }

                return error.InvalidFallbackValue;
            },
        }
    }

    pub fn decode(self: *AscIiFallback, slice: []const u8, cp: *Codepoint) DecodeError!u3 {
        if (slice.len == 0) return error.DecodeEmptySlice;
        if (slice[0] < 128) {
            cp.* = slice[0];
            return 1;
        }

        switch (self.strategy) {
            .Ignore => return 0,
            .RaiseError => return error.InvalidByte,
            else => {
                const char = self.strategy.resolve(slice[0]) catch unreachable;

                if (char < 128) {
                    cp.* = @truncate(u8, char);
                    return 1;
                }

                return error.InvalidFallbackValue;
            },
        }
    }

    pub fn pushByte(self: *AscIiFallback, byte: u8) DecodeError!?Codepoint {
        var cp: Codepoint = undefined;

        if (0 == try decode(self, &[_]u8{byte}, &cp)) {
            return null;
        }

        return cp;
    }
};

const t = std.testing;

fn evenOddFallback(missing: Codepoint) Codepoint {
    return if (missing & 1 == 0) '#' else '$';
}

const CircularTenFallback = struct {
    index: usize,

    pub fn fallback(self: *@This(), missing: Codepoint) Codepoint {
        const ans = self.index % 10;
        self.index += 1;

        return @truncate(Codepoint, '0' + ans);
    }
};

test "AscII Decoder" {
    var decoder = AsciiEncoding.decoder();

    t.expectEqual(decoder.codepoint("H"), 'H');
    t.expectEqual(decoder.codepoint("\t"), '\t');
    t.expectError(error.InvalidByte, decoder.codepoint("\x80"));
    t.expectError(error.InvalidByte, decoder.codepoint("\xFF"));
    t.expectError(error.DecodeEmptySlice, decoder.length(""));

    decoder.context.strategy = .Ignore;

    t.expectEqual(decoder.length("\x80"), 0);
    t.expectEqual(decoder.length("\x7F"), 1);

    decoder.context.strategy = encoding.FallbackStrategy.fromChar('?');

    t.expectEqual(decoder.length("\x80"), 1);
    t.expectEqual(decoder.codepoint("\x80"), '?');

    decoder.context.strategy = encoding.FallbackStrategy.fromFn(evenOddFallback);

    t.expectEqual(decoder.codepoint("\x80"), '#');
    t.expectEqual(decoder.codepoint("\x81"), '$');

    var circular = CircularTenFallback{ .index = 0 };
    decoder.context.strategy = encoding.FallbackStrategy.fromMethod(&circular, CircularTenFallback.fallback);

    t.expectEqual(decoder.codepoint("\x80"), '0');
    t.expectEqual(decoder.codepoint("\x80"), '1');
    t.expectEqual(decoder.codepoint("\x80"), '2');
    t.expectEqual(decoder.codepoint("\x80"), '3');
    t.expectEqual(decoder.codepoint("\x80"), '4');
    t.expectEqual(decoder.codepoint("\x80"), '5');
    t.expectEqual(decoder.codepoint("\x80"), '6');
    t.expectEqual(decoder.codepoint("\x80"), '7');
    t.expectEqual(decoder.codepoint("\x80"), '8');
    t.expectEqual(decoder.codepoint("\x80"), '9');
    t.expectEqual(decoder.codepoint("\x80"), '0');

    decoder.context.strategy = encoding.FallbackStrategy.fromChar('ᥠ');

    t.expectError(error.InvalidFallbackValue, decoder.codepoint("\xff"));
}

test "AscII Stateful" {
    var decoder = AsciiEncoding.stateful();

    t.expectEqual(decoder.pushByte('H'), 'H');
    t.expectEqual(decoder.pushByte('\t'), '\t');
    t.expectError(error.InvalidByte, decoder.pushByte(0x80));
    t.expectError(error.InvalidByte, decoder.pushByte(0xFF));

    decoder.context.strategy = .Ignore;

    t.expectEqual(decoder.pushByte(0x80), null);
    t.expectEqual(decoder.pushByte(0x7F), '\x7F');

    decoder.context.strategy = encoding.FallbackStrategy.fromChar('?');

    t.expectEqual(decoder.pushByte(0x80), '?');

    decoder.context.strategy = encoding.FallbackStrategy.fromFn(evenOddFallback);

    t.expectEqual(decoder.pushByte(0x80), '#');
    t.expectEqual(decoder.pushByte(0x81), '$');

    var circular = CircularTenFallback{ .index = 0 };
    decoder.context.strategy = encoding.FallbackStrategy.fromMethod(&circular, CircularTenFallback.fallback);

    t.expectEqual(decoder.pushByte(0x80), '0');
    t.expectEqual(decoder.pushByte(0x80), '1');
    t.expectEqual(decoder.pushByte(0x80), '2');
    t.expectEqual(decoder.pushByte(0x80), '3');
    t.expectEqual(decoder.pushByte(0x80), '4');
    t.expectEqual(decoder.pushByte(0x80), '5');
    t.expectEqual(decoder.pushByte(0x80), '6');
    t.expectEqual(decoder.pushByte(0x80), '7');
    t.expectEqual(decoder.pushByte(0x80), '8');
    t.expectEqual(decoder.pushByte(0x80), '9');
    t.expectEqual(decoder.pushByte(0x80), '0');

    decoder.context.strategy = encoding.FallbackStrategy.fromChar('ᥠ');

    t.expectError(error.InvalidFallbackValue, decoder.pushByte(0xff));
}

test "AscII Encoder" {
    var encoder = AsciiEncoding.encoder();
    var buff: [1]u8 = undefined;
    var slice: []u8 = &buff;
    
    t.expect(std.mem.eql(u8, "H", try encoder.slice('H', slice)));
    t.expect(std.mem.eql(u8, "\t", try encoder.slice('\t', slice)));
    t.expectError(error.InsufficientSpace, encoder.encode('W', slice[1..]));
    t.expectError(error.UnmappedCodepoint, encoder.slice(0xFF, slice));

    encoder.context.strategy = .Ignore;

    t.expectEqual(encoder.length(0x80), 0);
    t.expectEqual(encoder.length(0x7F), 1);

    encoder.context.strategy = encoding.FallbackStrategy.fromChar('?');

    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "?"));

    encoder.context.strategy = encoding.FallbackStrategy.fromFn(evenOddFallback);

    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "#"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x81, slice), "$"));

    var circular = CircularTenFallback{ .index = 0 };
    encoder.context.strategy = encoding.FallbackStrategy.fromMethod(&circular, CircularTenFallback.fallback);

    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "0"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "1"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "2"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "3"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "4"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "5"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "6"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "7"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "8"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "9"));
    t.expect(std.mem.eql(u8, try encoder.slice(0x80, slice), "0"));

    encoder.context.strategy = encoding.FallbackStrategy.fromChar('ᥠ');

    t.expectError(error.InvalidFallbackValue, encoder.encode(0xff, slice[0..]));
}
