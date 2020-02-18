const std = @import("std");
pub const Utf8Encoding = @import("utf_8.zig");
pub const Utf16Encoding = @import("utf_16.zig");

test "nothing" {
    const utf = Utf8Encoding{};
    const ut1 = Utf16Encoding{};
}

pub fn main() void {
    var heap = std.heap.HeapAllocator.init();
    defer heap.deinit();
    var alloc = &heap.allocator;

    var dir = std.fs.cwd().openDirList("tables") catch return;
    defer dir.close();

    var buffer = std.Buffer.initCapacity(alloc, 0) catch {
        std.debug.warn("Not enough memory!\n", .{});
        return;
    };
    defer buffer.deinit();

    var it = dir.iterate();
    while (it.next() catch |e| brk: {
        std.debug.warn("{}\n", .{@errorName(e)});
        break :brk std.fs.Dir.Entry{
            .name = "Error, could not retrieve entry",
            .kind = .Unknown,
        };
    }) |entry| {
        std.debug.warn("Kind: {} Filename: {}\n", .{ std.meta.tagName(entry.kind), entry.name });

        var file = dir.openFile(entry.name, .{}) catch |e| {
            std.debug.warn("Error opening file, {}\n", .{@errorName(e)});
            continue;
        };
        defer file.close();

        var in_stream = file.inStream();
        var shouldBreak = false;
        
        while (true) {
            defer buffer.resize(0) catch unreachable;

            var line = std.io.readLineFrom(&in_stream.stream, &buffer) catch |e| brk: {
                switch (e) {
                    error.EndOfStream => {
                        shouldBreak = true;
                        break :brk buffer.toSlice();
                    },
                    else => {
                        std.debug.warn("Error reading file, {}\n", .{@errorName(e)});
                        break;
                    }
                }
            };

            if (shouldBreak and line.len == 0)
                break;

            if (std.mem.startsWith(u8, line, "#"))
                continue;
                
            var digit_index = std.mem.indexOfAny(u8, line, "1234567890") orelse {
                continue;
            };
            var space_index = std.mem.indexOfAnyPos(u8, line, digit_index, " \t") orelse line.len;

            const index = std.fmt.parseUnsigned(u8, line[digit_index..space_index], 10) catch unreachable;

            if (space_index == line.len)
                continue;

            digit_index = std.mem.indexOfAnyPos(u8, line, space_index, "x") orelse {
                continue;
            };
            digit_index += 1;
            space_index = std.mem.indexOfAnyPos(u8, line, digit_index, " \t") orelse line.len;

            const codepoint = std.fmt.parseUnsigned(u21, line[digit_index..space_index], 16) catch unreachable;
            
            std.debug.warn("{X:0<8}\n", .{ (@as(u32, codepoint) << 8) | index });
        }

        std.debug.warn("\n\n\n\n\n", .{});
    }
}
