use crate::{Error, Header, Result};

#[derive(Debug, Default)]
pub struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            bytes: Vec::with_capacity(capacity),
        }
    }

    pub fn position(&self) -> usize {
        self.bytes.len()
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.bytes
    }

    pub fn into_inner(self) -> Vec<u8> {
        self.bytes
    }

    pub fn write_header(&mut self, header: Header) {
        self.write_u16(header.block_length);
        self.write_u16(header.template_id);
        self.write_u16(header.schema_id);
        self.write_u16(header.version);
    }

    pub fn write_u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    pub fn write_i8(&mut self, value: i8) {
        self.bytes.push(value as u8);
    }

    pub fn write_u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_i16(&mut self, value: i16) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_i32(&mut self, value: i32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_u64(&mut self, value: u64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_i64(&mut self, value: i64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn write_f32(&mut self, value: f32) {
        self.write_u32(value.to_bits());
    }

    pub fn write_f64(&mut self, value: f64) {
        self.write_u64(value.to_bits());
    }

    pub fn write_bool(&mut self, value: Option<bool>) {
        self.write_u8(match value {
            Some(false) => 0,
            Some(true) => 1,
            None => 255,
        });
    }

    pub fn write_uuid(&mut self, value: Option<&[u8; 16]>) {
        self.bytes.extend_from_slice(value.unwrap_or(&[0; 16]));
    }

    pub fn write_string8(&mut self, value: Option<&str>) -> Result<()> {
        self.write_bytes8(value.map(str::as_bytes))
    }

    pub fn write_string16(&mut self, value: Option<&str>) -> Result<()> {
        self.write_bytes16(value.map(str::as_bytes))
    }

    pub fn write_string32(&mut self, value: Option<&str>) -> Result<()> {
        self.write_bytes32(value.map(str::as_bytes))
    }

    pub fn write_bytes8(&mut self, value: Option<&[u8]>) -> Result<()> {
        let value = value.unwrap_or_default();
        let length = u8::try_from(value.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 8,
            length: value.len(),
        })?;
        self.write_u8(length);
        self.bytes.extend_from_slice(value);
        Ok(())
    }

    pub fn write_bytes16(&mut self, value: Option<&[u8]>) -> Result<()> {
        let value = value.unwrap_or_default();
        let length = u16::try_from(value.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 16,
            length: value.len(),
        })?;
        self.write_u16(length);
        self.bytes.extend_from_slice(value);
        Ok(())
    }

    pub fn write_bytes32(&mut self, value: Option<&[u8]>) -> Result<()> {
        let value = value.unwrap_or_default();
        let length = u32::try_from(value.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 32,
            length: value.len(),
        })?;
        self.write_u32(length);
        self.bytes.extend_from_slice(value);
        Ok(())
    }

    pub fn write_group_header(&mut self, block_length: u16, count: u16) {
        self.write_u16(block_length);
        self.write_u16(count);
    }

    pub fn verify_fixed_block(&self, payload_start: usize, declared: u16) -> Result<()> {
        let actual = self.position().saturating_sub(payload_start);
        if actual != usize::from(declared) {
            return Err(Error::FixedBlockLengthMismatch { declared, actual });
        }
        Ok(())
    }
}
