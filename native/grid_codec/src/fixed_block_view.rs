use crate::{Error, Header, Result};

#[derive(Clone, Copy, Debug)]
pub struct FixedBlockView<
    'a,
    const BLOCK_LENGTH: usize,
    const SCHEMA_ID: u16,
    const TEMPLATE_ID: u16,
> {
    bytes: &'a [u8],
    fixed: &'a [u8; BLOCK_LENGTH],
    tail: &'a [u8],
}

impl<'a, const BLOCK_LENGTH: usize, const SCHEMA_ID: u16, const TEMPLATE_ID: u16>
    FixedBlockView<'a, BLOCK_LENGTH, SCHEMA_ID, TEMPLATE_ID>
{
    pub fn new(bytes: &'a [u8]) -> Result<Self> {
        let (header, payload) = Header::decode(bytes)?;
        header.expect_identity(SCHEMA_ID, TEMPLATE_ID)?;
        if usize::from(header.block_length) != BLOCK_LENGTH {
            return Err(Error::FixedBlockLengthMismatch {
                declared: header.block_length,
                actual: BLOCK_LENGTH,
            });
        }
        let fixed = payload
            .get(..BLOCK_LENGTH)
            .ok_or(Error::InsufficientData {
                needed: BLOCK_LENGTH,
                remaining: payload.len(),
            })?
            .try_into()
            .expect("validated fixed block length");
        Ok(Self {
            bytes,
            fixed,
            tail: &payload[BLOCK_LENGTH..],
        })
    }

    #[inline(always)]
    pub fn bytes(self) -> &'a [u8] {
        self.bytes
    }

    #[inline(always)]
    pub fn fixed(self) -> &'a [u8; BLOCK_LENGTH] {
        self.fixed
    }

    #[inline(always)]
    pub fn tail(self) -> &'a [u8] {
        self.tail
    }

    #[inline(always)]
    pub fn u32_at(self, offset: usize) -> u32 {
        u32::from_le_bytes(
            self.fixed[offset..offset + 4]
                .try_into()
                .expect("generated offset"),
        )
    }

    #[inline(always)]
    pub fn u64_at(self, offset: usize) -> u64 {
        u64::from_le_bytes(
            self.fixed[offset..offset + 8]
                .try_into()
                .expect("generated offset"),
        )
    }
}
