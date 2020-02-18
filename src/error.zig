/// Errors that can happen while decoding
pub const DecodeError = error{
    /// There's a surrogate encoded
    DecodeSurrogate,

    /// Attempt to decode an empty slice
    DecodeEmptySlice,

    /// Codepoint could be encoded using less bytes
    OverlongEncoding,

    /// There are less elements in the slice than needed for the sequence
    UnexpectedSequenceEnd,
};

/// Errors that can happen while decoding
/// Remarks: Read sequence as an UTF-16 encoded word sequence of a codepoint
pub const Utf16DecodeError = DecodeError || CodepointError || error{
    /// When the low surrogate appears first
    WrongSurrogateOrder,

    /// Expected low surrogate but there was none
    ExpectedLowSurrogate,
};
