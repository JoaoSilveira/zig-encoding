# Zig Encoding

This project intend to provide a way to deal with text encoding conversions.

There is a plan to create a String type that will hold the encoding of the text, number of characters (**NOT BYTES**) and utility functions to work with text processing. It's not sure but probably the string will be mutable, meaning, it will also hold an allocator to grow in size and it will be possible to apply operations to its content, somewhat similar to `std.Buffer`.

Intended use (**NOT WORKING YET**):

```zig
const encoding = @import("encoding.zig");

var string = encoding.utf16le("Converting comptime literal to other encoding");
```

```zig
const encoding = @import("encoding.zig");

// Can provide a default encoding
const DefaultEncoding = encoding.AscIi;

// this will convert the UTF-8 literal to the default encoding
var string = encoding.lit("Convert a literal to the default encoding");
```

```zig
const std = @import("std");
const encoding = @import("encoding.zig");

var string = "Runtime string value";
var target = encoding.convertToAlloc(encoding.Utf8, string, encoding.Windows874, &std.heap.c_allocator) catch unreachable;
```