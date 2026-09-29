use crate::{Decode, Encode, Header, Reader, Result, Writer};

pub const BLOCK_LENGTH: u16 = 13;
pub const TEMPLATE_ID: u16 = 65_000;
pub const SCHEMA_ID: u16 = 65_001;
pub const VERSION: u16 = 1;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BenchmarkMessage<'a> {
    pub number: u32,
    pub signed: i64,
    pub active: bool,
    pub name: &'a str,
}

impl Encode for BenchmarkMessage<'_> {
    fn header(&self) -> Header {
        Header {
            block_length: BLOCK_LENGTH,
            template_id: TEMPLATE_ID,
            schema_id: SCHEMA_ID,
            version: VERSION,
        }
    }

    fn encode_payload(&self, writer: &mut Writer) -> Result<()> {
        let payload_start = writer.position();
        writer.write_u32(self.number);
        writer.write_i64(self.signed);
        writer.write_bool(Some(self.active));
        writer.verify_fixed_block(payload_start, BLOCK_LENGTH)?;
        writer.write_string8(Some(self.name))
    }
}

impl<'a> Decode<'a> for BenchmarkMessage<'a> {
    const SCHEMA_ID: u16 = SCHEMA_ID;
    const TEMPLATE_ID: u16 = TEMPLATE_ID;
    const MIN_VERSION: u16 = VERSION;
    const MAX_VERSION: u16 = VERSION;

    fn decode_payload(_header: Header, reader: &mut Reader<'a>) -> Result<Self> {
        let number = reader.read_u32()?;
        let signed = reader.read_i64()?;
        let active = reader.read_bool()?.unwrap_or(false);
        let name = reader.read_string8()?.unwrap_or_default();

        Ok(Self {
            number,
            signed,
            active,
            name,
        })
    }
}

pub fn get_number(bytes: &[u8]) -> Result<u32> {
    let mut reader = Reader::new(bytes);
    let header = reader.read_header()?;
    header.expect_identity(SCHEMA_ID, TEMPLATE_ID)?;
    header.expect_version(VERSION, VERSION)?;
    reader.read_u32()
}
