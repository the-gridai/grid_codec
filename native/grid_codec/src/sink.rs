use crate::{Error, Header, Result};

pub trait Sink {
    fn position(&self) -> usize;
    fn write_raw(&mut self, value: &[u8]) -> Result<()>;

    #[inline]
    fn write_header(&mut self, header: Header) -> Result<()> {
        self.write_raw(&header.encode())
    }

    #[inline]
    fn write_u8(&mut self, value: u8) -> Result<()> {
        self.write_raw(&[value])
    }

    #[inline]
    fn write_i8(&mut self, value: i8) -> Result<()> {
        self.write_u8(value as u8)
    }

    #[inline]
    fn write_u16(&mut self, value: u16) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_i16(&mut self, value: i16) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_u32(&mut self, value: u32) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_i32(&mut self, value: i32) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_u64(&mut self, value: u64) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_i64(&mut self, value: i64) -> Result<()> {
        self.write_raw(&value.to_le_bytes())
    }

    #[inline]
    fn write_bool(&mut self, value: Option<bool>) -> Result<()> {
        self.write_u8(match value {
            Some(false) => 0,
            Some(true) => 1,
            None => 255,
        })
    }

    #[inline]
    fn write_string8(&mut self, value: Option<&str>) -> Result<()> {
        let value = value.unwrap_or_default().as_bytes();
        let length = u8::try_from(value.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 8,
            length: value.len(),
        })?;
        self.write_u8(length)?;
        self.write_raw(value)
    }

    #[inline]
    fn write_string16(&mut self, value: Option<&str>) -> Result<()> {
        let value = value.unwrap_or_default().as_bytes();
        let length = u16::try_from(value.len()).map_err(|_| Error::LengthOverflow {
            prefix_bits: 16,
            length: value.len(),
        })?;
        self.write_u16(length)?;
        self.write_raw(value)
    }

    #[inline]
    fn verify_fixed_block(&self, payload_start: usize, declared: u16) -> Result<()> {
        let actual = self.position().saturating_sub(payload_start);
        if actual != usize::from(declared) {
            return Err(Error::FixedBlockLengthMismatch { declared, actual });
        }
        Ok(())
    }
}

impl Sink for crate::Writer {
    #[inline]
    fn position(&self) -> usize {
        self.position()
    }

    #[inline]
    fn write_raw(&mut self, value: &[u8]) -> Result<()> {
        self.write_raw(value);
        Ok(())
    }
}

#[derive(Debug)]
pub struct SliceWriter<'a> {
    bytes: &'a mut [u8],
    position: usize,
}

impl<'a> SliceWriter<'a> {
    pub fn new(bytes: &'a mut [u8]) -> Self {
        Self { bytes, position: 0 }
    }
}

impl Sink for SliceWriter<'_> {
    #[inline]
    fn position(&self) -> usize {
        self.position
    }

    #[inline]
    fn write_raw(&mut self, value: &[u8]) -> Result<()> {
        let end = self
            .position
            .checked_add(value.len())
            .ok_or(Error::InsufficientData {
                needed: value.len(),
                remaining: self.bytes.len().saturating_sub(self.position),
            })?;
        let remaining = self.bytes.len().saturating_sub(self.position);
        let output = self
            .bytes
            .get_mut(self.position..end)
            .ok_or(Error::InsufficientData {
                needed: value.len(),
                remaining,
            })?;
        output.copy_from_slice(value);
        self.position = end;
        Ok(())
    }
}
