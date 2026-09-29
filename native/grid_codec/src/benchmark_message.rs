use std::mem::size_of;

use crate::{Decode, Encode, Error, Header, Reader, Result};

pub const BLOCK_LENGTH: u16 = 13;
pub const TEMPLATE_ID: u16 = 65_000;
pub const SCHEMA_ID: u16 = 65_001;
pub const VERSION: u16 = 1;
pub const NUMBER_OFFSET: usize = crate::HEADER_SIZE;
pub const SIGNED_OFFSET: usize = NUMBER_OFFSET + size_of::<u32>();
pub const ACTIVE_OFFSET: usize = SIGNED_OFFSET + size_of::<i64>();
pub const NAME_LENGTH_OFFSET: usize = ACTIVE_OFFSET + size_of::<u8>();
pub const NAME_OFFSET: usize = NAME_LENGTH_OFFSET + size_of::<u8>();

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BenchmarkMessage<'a> {
    pub number: u32,
    pub signed: i64,
    pub active: bool,
    pub name: &'a str,
}

impl BenchmarkMessage<'_> {
    pub fn encoded_len(&self) -> Result<usize> {
        u8::try_from(self.name.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 8,
            length: self.name.len(),
        })?;
        Ok(NAME_OFFSET + self.name.len())
    }

    pub fn encode_into(&self, output: &mut [u8]) -> Result<usize> {
        let encoded_len = self.encoded_len()?;
        let remaining = output.len();
        let output = output
            .get_mut(..encoded_len)
            .ok_or(Error::InsufficientData {
                needed: encoded_len,
                remaining,
            })?;
        output[..crate::HEADER_SIZE]
            .copy_from_slice(&Header::new(BLOCK_LENGTH, TEMPLATE_ID, SCHEMA_ID, VERSION).encode());
        output[NUMBER_OFFSET..SIGNED_OFFSET].copy_from_slice(&self.number.to_le_bytes());
        output[SIGNED_OFFSET..ACTIVE_OFFSET].copy_from_slice(&self.signed.to_le_bytes());
        output[ACTIVE_OFFSET] = u8::from(self.active);
        output[NAME_LENGTH_OFFSET] = self.name.len() as u8;
        output[NAME_OFFSET..].copy_from_slice(self.name.as_bytes());
        Ok(encoded_len)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct BenchmarkMessageView<'a> {
    bytes: &'a [u8],
}

impl<'a> BenchmarkMessageView<'a> {
    pub fn new(bytes: &'a [u8]) -> Result<Self> {
        let (header, payload) = Header::decode(bytes)?;
        header.expect_identity(SCHEMA_ID, TEMPLATE_ID)?;
        header.expect_version(VERSION, VERSION)?;
        let fixed_and_length =
            payload
                .get(..BLOCK_LENGTH as usize + 1)
                .ok_or(Error::InsufficientData {
                    needed: BLOCK_LENGTH as usize + 1,
                    remaining: payload.len(),
                })?;
        match fixed_and_length[ACTIVE_OFFSET - crate::HEADER_SIZE] {
            0 | 1 => {}
            value => return Err(Error::InvalidBool(value)),
        }
        let name_length = usize::from(fixed_and_length[BLOCK_LENGTH as usize]);
        let encoded_len = NAME_OFFSET + name_length;
        let remaining = bytes.len();
        let bytes = bytes.get(..encoded_len).ok_or(Error::InsufficientData {
            needed: encoded_len,
            remaining,
        })?;
        std::str::from_utf8(&bytes[NAME_OFFSET..]).map_err(|_| Error::InvalidUtf8)?;
        Ok(Self { bytes })
    }

    #[inline(always)]
    pub fn number(self) -> u32 {
        u32::from_le_bytes([
            self.bytes[NUMBER_OFFSET],
            self.bytes[NUMBER_OFFSET + 1],
            self.bytes[NUMBER_OFFSET + 2],
            self.bytes[NUMBER_OFFSET + 3],
        ])
    }

    #[inline(always)]
    pub fn signed(self) -> i64 {
        i64::from_le_bytes([
            self.bytes[SIGNED_OFFSET],
            self.bytes[SIGNED_OFFSET + 1],
            self.bytes[SIGNED_OFFSET + 2],
            self.bytes[SIGNED_OFFSET + 3],
            self.bytes[SIGNED_OFFSET + 4],
            self.bytes[SIGNED_OFFSET + 5],
            self.bytes[SIGNED_OFFSET + 6],
            self.bytes[SIGNED_OFFSET + 7],
        ])
    }

    #[inline(always)]
    pub fn active(self) -> bool {
        self.bytes[ACTIVE_OFFSET] == 1
    }

    #[inline(always)]
    pub fn name(self) -> &'a str {
        std::str::from_utf8(&self.bytes[NAME_OFFSET..])
            .expect("BenchmarkMessageView validates UTF-8 during construction")
    }
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

    fn encoded_len(&self) -> Result<usize> {
        BenchmarkMessage::encoded_len(self)
    }

    fn encode_payload<S: crate::Sink>(&self, writer: &mut S) -> Result<()> {
        let payload_start = writer.position();
        let mut fixed = [0; BLOCK_LENGTH as usize];
        fixed[0..4].copy_from_slice(&self.number.to_le_bytes());
        fixed[4..12].copy_from_slice(&self.signed.to_le_bytes());
        fixed[12] = u8::from(self.active);
        writer.write_raw(&fixed)?;
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
