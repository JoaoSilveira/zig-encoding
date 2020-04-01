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
pub fn isSurrogate(codepoint: Codepoint) bool {
    return codepoint >= surrogate_min and codepoint <= surrogate_max;
}

/// Tells if codepoint is a high surrogate
pub fn isHighSurrogate(codepoint: Codepoint) bool {
    return codepoint >= surrogate_min and codepoint <= high_surrogate_max;
}

/// Tells if codepoint is low surrogate
pub fn isLowSurrogate(codepoint: Codepoint) bool {
    return codepoint > high_surrogate_max and codepoint <= surrogate_max;
}

/// Invalid codepoint value
pub const CodepointError = error{
    /// Indicates a codepoint value greater than 0x10FFFF
    InvalidCodepointValue,
};
