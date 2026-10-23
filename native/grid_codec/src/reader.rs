use crate::{Error, Header, Result};

#[derive(Clone, Copy, Debug)]
pub struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    pub const fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    pub const fn position(&self) -> usize {
        self.offset
    }

    pub fn remaining(&self) -> &'a [u8] {
        &self.bytes[self.offset..]
    }

    pub fn require(&self, needed: usize) -> Result<()> {
        let remaining = self.bytes.len().saturating_sub(self.offset);
        if remaining < needed {
            return Err(Error::InsufficientData { needed, remaining });
        }
        Ok(())
    }

    pub fn read_exact(&mut self, length: usize) -> Result<&'a [u8]> {
        self.require(length)?;
        let start = self.offset;
        self.offset += length;
        Ok(&self.bytes[start..self.offset])
    }

    pub fn skip(&mut self, length: usize) -> Result<()> {
        self.read_exact(length).map(|_| ())
    }

    pub fn read_header(&mut self) -> Result<Header> {
        Ok(Header {
            block_length: self.read_u16()?,
            template_id: self.read_u16()?,
            schema_id: self.read_u16()?,
            version: self.read_u16()?,
        })
    }

    pub fn read_u8(&mut self) -> Result<u8> {
        Ok(self.read_exact(1)?[0])
    }

    pub fn read_i8(&mut self) -> Result<i8> {
        Ok(self.read_u8()? as i8)
    }

    pub fn read_u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.read_exact(2)?.try_into().unwrap()))
    }

    pub fn read_i16(&mut self) -> Result<i16> {
        Ok(i16::from_le_bytes(self.read_exact(2)?.try_into().unwrap()))
    }

    pub fn read_u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.read_exact(4)?.try_into().unwrap()))
    }

    pub fn read_i32(&mut self) -> Result<i32> {
        Ok(i32::from_le_bytes(self.read_exact(4)?.try_into().unwrap()))
    }

    pub fn read_u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.read_exact(8)?.try_into().unwrap()))
    }

    pub fn read_i64(&mut self) -> Result<i64> {
        Ok(i64::from_le_bytes(self.read_exact(8)?.try_into().unwrap()))
    }

    pub fn read_f32(&mut self) -> Result<f32> {
        Ok(f32::from_bits(self.read_u32()?))
    }

    pub fn read_f64(&mut self) -> Result<f64> {
        Ok(f64::from_bits(self.read_u64()?))
    }

    pub fn read_bool(&mut self) -> Result<Option<bool>> {
        match self.read_u8()? {
            0 => Ok(Some(false)),
            1 => Ok(Some(true)),
            255 => Ok(None),
            value => Err(Error::InvalidBool(value)),
        }
    }

    pub fn read_uuid(&mut self) -> Result<Option<&'a [u8; 16]>> {
        let value: &'a [u8; 16] = self.read_exact(16)?.try_into().unwrap();
        if value.iter().all(|byte| *byte == 0) {
            Ok(None)
        } else {
            Ok(Some(value))
        }
    }

    pub fn read_string8(&mut self) -> Result<Option<&'a str>> {
        let length = self.read_u8()? as usize;
        self.read_optional_str(length)
    }

    pub fn read_string16(&mut self) -> Result<Option<&'a str>> {
        let length = self.read_u16()? as usize;
        self.read_optional_str(length)
    }

    pub fn read_string32(&mut self) -> Result<Option<&'a str>> {
        let length = self.read_u32()? as usize;
        self.read_optional_str(length)
    }

    pub fn read_bytes8(&mut self) -> Result<Option<&'a [u8]>> {
        let length = self.read_u8()? as usize;
        self.read_optional_bytes(length)
    }

    pub fn read_bytes16(&mut self) -> Result<Option<&'a [u8]>> {
        let length = self.read_u16()? as usize;
        self.read_optional_bytes(length)
    }

    pub fn read_bytes32(&mut self) -> Result<Option<&'a [u8]>> {
        let length = self.read_u32()? as usize;
        self.read_optional_bytes(length)
    }

    pub fn read_group_header(&mut self) -> Result<(u16, u16)> {
        Ok((self.read_u16()?, self.read_u16()?))
    }

    fn read_optional_str(&mut self, length: usize) -> Result<Option<&'a str>> {
        match self.read_optional_bytes(length)? {
            None => Ok(None),
            Some(bytes) => std::str::from_utf8(bytes)
                .map(Some)
                .map_err(|_| Error::InvalidUtf8),
        }
    }

    fn read_optional_bytes(&mut self, length: usize) -> Result<Option<&'a [u8]>> {
        if length == 0 {
            return Ok(None);
        }
        self.read_exact(length).map(Some)
    }
}
