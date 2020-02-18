pub const Codepoint = u21;

/// the greatest value a codepoint can have
pub const codepoint_max = 0x10FFFF;

/// the minimum value of a surrogate;
pub const surrogate_min = 0xD800;

/// the maximum value of a surrogate
pub const surrogate_max = 0xDFFF;

/// the maximum value of a high surrogate
pub const high_surrogate_max = 0xDBFF;

/// Tells if codepoint is a surrogate
pub fn isSurrogate(codepoint: u32) bool {
    return codepoint >= surrogate_min and codepoint <= surrogate_max;
}

/// Tells if codepoint is a high surrogate
pub fn isHighSurrogate(codepoint: u32) bool {
    return codepoint >= surrogate_min and codepoint <= high_surrogate_max;
}

/// Tells if codepoint is low surrogate
pub fn isLowSurrogate(codepoint: u32) bool {
    return codepoint > high_surrogate_max and codepoint <= surrogate_max;
}

/// Tells if the codepoint is larger than 16 bits
pub fn isLargeCodepoint(codepoint: u32) bool {
    return codepoint > 0xFFFF;
}

/// Invalid codepoint value
pub const CodepointError = error{
    /// Indicates a codepoint value greater than 0x10FFFF
    InvalidCodepointValue,
};

/// Error that can happen during the encoding
pub const EncodeError = CodepointError || error{
    /// Attempt to encode a surrogate
    EncodingSurrogate,

    /// Slice is too short to hold the encoded sequence
    InsufficientSpace,
};

/// Any error while validating a slice
pub const ValidateSequenceError = error{InvalidSequence};