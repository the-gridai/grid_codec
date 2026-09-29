#![forbid(unsafe_code)]

pub mod benchmark_message;
mod error;
mod header;
mod reader;
mod writer;

pub use benchmark_message::BenchmarkMessage;
pub use error::{Error, Result};
pub use header::{Header, HEADER_SIZE};
pub use reader::Reader;
pub use writer::Writer;

pub trait Encode {
    fn header(&self) -> Header;
    fn encode_payload(&self, writer: &mut Writer) -> Result<()>;

    fn encoded_len_hint(&self) -> usize {
        let header = self.header();
        HEADER_SIZE + usize::from(header.block_length)
    }

    fn encode_to(&self, writer: &mut Writer) -> Result<()> {
        let header = self.header();
        writer.clear();
        writer.reserve(self.encoded_len_hint());
        writer.write_header(header);
        self.encode_payload(writer)
    }

    fn encode(&self) -> Result<Vec<u8>> {
        let mut writer = Writer::with_capacity(self.encoded_len_hint());
        self.encode_to(&mut writer)?;
        Ok(writer.into_inner())
    }
}

pub trait Decode<'a>: Sized {
    const SCHEMA_ID: u16;
    const TEMPLATE_ID: u16;
    const MIN_VERSION: u16 = 1;
    const MAX_VERSION: u16 = u16::MAX;

    fn decode_payload(header: Header, reader: &mut Reader<'a>) -> Result<Self>;

    fn decode(bytes: &'a [u8]) -> Result<Self> {
        let mut reader = Reader::new(bytes);
        let header = reader.read_header()?;
        header.expect_identity(Self::SCHEMA_ID, Self::TEMPLATE_ID)?;
        header.expect_version(Self::MIN_VERSION, Self::MAX_VERSION)?;
        reader.require(header.block_length as usize)?;
        Self::decode_payload(header, &mut reader)
    }
}
