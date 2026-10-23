use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum Error {
    #[error("insufficient data: need {needed} bytes, only {remaining} remain")]
    InsufficientData { needed: usize, remaining: usize },
    #[error("wrong schema: expected {expected}, received {actual}")]
    WrongSchema { expected: u16, actual: u16 },
    #[error("wrong template: expected {expected}, received {actual}")]
    WrongTemplate { expected: u16, actual: u16 },
    #[error("unsupported version {actual}; expected {minimum}..={maximum}")]
    UnsupportedVersion {
        minimum: u16,
        maximum: u16,
        actual: u16,
    },
    #[error("invalid boolean byte {0}")]
    InvalidBool(u8),
    #[error("value is too long for a {prefix_bits}-bit length prefix: {length} bytes")]
    LengthOverflow { prefix_bits: u8, length: usize },
    #[error("invalid UTF-8")]
    InvalidUtf8,
    #[error("fixed block length mismatch: header declares {declared}, encoder wrote {actual}")]
    FixedBlockLengthMismatch { declared: u16, actual: usize },
}
