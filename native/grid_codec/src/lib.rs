#![forbid(unsafe_code)]

pub mod benchmark_message;
mod error;
mod fixed_block_view;
mod header;
mod reader;
mod sink;
mod writer;

pub use benchmark_message::{BenchmarkMessage, BenchmarkMessageView};
pub use error::{Error, Result};
pub use fixed_block_view::FixedBlockView;
pub use header::{Header, HEADER_SIZE};
pub use reader::Reader;
pub use sink::{Sink, SliceWriter};
pub use writer::Writer;

pub trait Encode {
    fn header(&self) -> Header;
    fn encode_payload<S: Sink>(&self, writer: &mut S) -> Result<()>;

    fn encoded_len(&self) -> Result<usize>;

    fn encode_to(&self, writer: &mut Writer) -> Result<()> {
        let encoded_len = self.encoded_len()?;
        writer.clear();
        writer.resize(encoded_len);
        let written = self.encode_into(writer.as_mut_slice())?;
        writer.truncate(written);
        Ok(())
    }

    fn encode_into(&self, output: &mut [u8]) -> Result<usize> {
        let header = self.header();
        let mut writer = SliceWriter::new(output);
        writer.write_header(header)?;
        self.encode_payload(&mut writer)?;
        Ok(writer.position())
    }

    fn encode(&self) -> Result<Vec<u8>> {
        let encoded_len = self.encoded_len()?;
        let mut bytes = vec![0; encoded_len];
        let written = self.encode_into(&mut bytes)?;
        bytes.truncate(written);
        Ok(bytes)
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
        Self::decode_payload(header, &mut reader)
    }
}
