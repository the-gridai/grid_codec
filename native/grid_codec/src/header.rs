use crate::{Error, Result};

pub const HEADER_SIZE: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Header {
    pub block_length: u16,
    pub template_id: u16,
    pub schema_id: u16,
    pub version: u16,
}

impl Header {
    pub const fn new(block_length: u16, template_id: u16, schema_id: u16, version: u16) -> Self {
        Self {
            block_length,
            template_id,
            schema_id,
            version,
        }
    }

    pub fn encode(self) -> [u8; HEADER_SIZE] {
        let mut bytes = [0; HEADER_SIZE];
        bytes[0..2].copy_from_slice(&self.block_length.to_le_bytes());
        bytes[2..4].copy_from_slice(&self.template_id.to_le_bytes());
        bytes[4..6].copy_from_slice(&self.schema_id.to_le_bytes());
        bytes[6..8].copy_from_slice(&self.version.to_le_bytes());
        bytes
    }

    pub fn decode(bytes: &[u8]) -> Result<(Self, &[u8])> {
        let header = bytes.get(..HEADER_SIZE).ok_or(Error::InsufficientData {
            needed: HEADER_SIZE,
            remaining: bytes.len(),
        })?;

        Ok((
            Self {
                block_length: u16::from_le_bytes([header[0], header[1]]),
                template_id: u16::from_le_bytes([header[2], header[3]]),
                schema_id: u16::from_le_bytes([header[4], header[5]]),
                version: u16::from_le_bytes([header[6], header[7]]),
            },
            &bytes[HEADER_SIZE..],
        ))
    }

    pub fn expect_identity(self, schema_id: u16, template_id: u16) -> Result<()> {
        if self.schema_id != schema_id {
            return Err(Error::WrongSchema {
                expected: schema_id,
                actual: self.schema_id,
            });
        }
        if self.template_id != template_id {
            return Err(Error::WrongTemplate {
                expected: template_id,
                actual: self.template_id,
            });
        }
        Ok(())
    }

    pub fn expect_version(self, minimum: u16, maximum: u16) -> Result<()> {
        if self.version < minimum || self.version > maximum {
            return Err(Error::UnsupportedVersion {
                minimum,
                maximum,
                actual: self.version,
            });
        }
        Ok(())
    }
}
