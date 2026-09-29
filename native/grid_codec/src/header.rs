use crate::{Error, Reader, Result, Writer};

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
        let mut writer = Writer::with_capacity(HEADER_SIZE);
        writer.write_header(self);
        writer
            .into_inner()
            .try_into()
            .expect("header always contains eight bytes")
    }

    pub fn decode(bytes: &[u8]) -> Result<(Self, &[u8])> {
        let mut reader = Reader::new(bytes);
        let header = reader.read_header()?;
        Ok((header, reader.remaining()))
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
