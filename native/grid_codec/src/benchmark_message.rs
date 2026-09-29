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

    fn encoded_len_hint(&self) -> usize {
        crate::HEADER_SIZE + BLOCK_LENGTH as usize + 1 + self.name.len()
    }

    fn encode_payload(&self, writer: &mut Writer) -> Result<()> {
        let payload_start = writer.position();
        let mut fixed = [0; BLOCK_LENGTH as usize];
        fixed[0..4].copy_from_slice(&self.number.to_le_bytes());
        fixed[4..12].copy_from_slice(&self.signed.to_le_bytes());
        fixed[12] = u8::from(self.active);
        writer.write_raw(&fixed);
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
        let fixed = reader.read_exact(BLOCK_LENGTH as usize)?;
        let number = u32::from_le_bytes([fixed[0], fixed[1], fixed[2], fixed[3]]);
        let signed = i64::from_le_bytes([
            fixed[4], fixed[5], fixed[6], fixed[7], fixed[8], fixed[9], fixed[10], fixed[11],
        ]);
        let active = match fixed[12] {
            0 => false,
            1 => true,
            value => return Err(crate::Error::InvalidBool(value)),
        };
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
    let (header, payload) = Header::decode(bytes)?;
    header.expect_identity(SCHEMA_ID, TEMPLATE_ID)?;
    header.expect_version(VERSION, VERSION)?;
    let number = payload.get(..4).ok_or(crate::Error::InsufficientData {
        needed: 4,
        remaining: payload.len(),
    })?;
    Ok(u32::from_le_bytes([
        number[0], number[1], number[2], number[3],
    ]))
}
