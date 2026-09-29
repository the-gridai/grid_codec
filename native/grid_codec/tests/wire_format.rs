use grid_codec::{
    BenchmarkMessage, Decode, Encode, Error, Header, Reader, Result, Writer, HEADER_SIZE,
};

#[test]
fn header_matches_grid_codec_little_endian_layout() {
    let header = Header::new(32, 1, 100, 2);
    assert_eq!(header.encode(), [32, 0, 1, 0, 100, 0, 2, 0]);

    let (decoded, rest) = Header::decode(&[32, 0, 1, 0, 100, 0, 2, 0, 9]).unwrap();
    assert_eq!(decoded, header);
    assert_eq!(rest, &[9]);
    assert_eq!(HEADER_SIZE, 8);
}

#[test]
fn primitives_and_variable_data_round_trip() {
    let uuid = [7u8; 16];
    let mut writer = Writer::new();
    writer.write_u32(42);
    writer.write_i64(-7);
    writer.write_bool(Some(true));
    writer.write_bool(None);
    writer.write_uuid(Some(&uuid));
    writer.write_string8(Some("grid")).unwrap();
    writer.write_string16(None).unwrap();
    writer.write_bytes32(Some(&[1, 2, 3])).unwrap();

    let bytes = writer.into_inner();
    let mut reader = Reader::new(&bytes);
    assert_eq!(reader.read_u32().unwrap(), 42);
    assert_eq!(reader.read_i64().unwrap(), -7);
    assert_eq!(reader.read_bool().unwrap(), Some(true));
    assert_eq!(reader.read_bool().unwrap(), None);
    assert_eq!(reader.read_uuid().unwrap(), Some(&uuid));
    assert_eq!(reader.read_string8().unwrap(), Some("grid"));
    assert_eq!(reader.read_string16().unwrap(), None);
    assert_eq!(reader.read_bytes32().unwrap(), Some([1, 2, 3].as_slice()));
    assert!(reader.remaining().is_empty());
}

#[derive(Debug, PartialEq, Eq)]
struct Example<'a> {
    sequence: u64,
    active: Option<bool>,
    name: Option<&'a str>,
}

impl Encode for Example<'_> {
    fn header(&self) -> Header {
        Header::new(9, 7, 3, 1)
    }

    fn encode_payload(&self, writer: &mut Writer) -> Result<()> {
        let payload_start = writer.position();
        writer.write_u64(self.sequence);
        writer.write_bool(self.active);
        writer.verify_fixed_block(payload_start, self.header().block_length)?;
        writer.write_string16(self.name)
    }
}

impl<'a> Decode<'a> for Example<'a> {
    const SCHEMA_ID: u16 = 3;
    const TEMPLATE_ID: u16 = 7;
    const MAX_VERSION: u16 = 1;

    fn decode_payload(header: Header, reader: &mut Reader<'a>) -> Result<Self> {
        let fixed_start = reader.position();
        let sequence = reader.read_u64()?;
        let active = reader.read_bool()?;
        let consumed = reader.position() - fixed_start;
        reader.skip(usize::from(header.block_length).saturating_sub(consumed))?;
        let name = reader.read_string16()?;
        Ok(Self {
            sequence,
            active,
            name,
        })
    }
}

#[test]
fn typed_message_round_trips_without_copying_variable_data() {
    let encoded = Example {
        sequence: 99,
        active: Some(false),
        name: Some("magic"),
    }
    .encode()
    .unwrap();

    assert_eq!(
        Example::decode(&encoded).unwrap(),
        Example {
            sequence: 99,
            active: Some(false),
            name: Some("magic"),
        }
    );
}

#[test]
fn identity_and_bounds_errors_are_structured() {
    let wrong_schema = Header::new(0, 7, 4, 1).encode();
    assert_eq!(
        Example::decode(&wrong_schema),
        Err(Error::WrongSchema {
            expected: 3,
            actual: 4,
        })
    );

    let mut reader = Reader::new(&[1]);
    assert_eq!(
        reader.read_u16(),
        Err(Error::InsufficientData {
            needed: 2,
            remaining: 1,
        })
    );
}

#[test]
fn group_header_matches_grid_codec_layout() {
    let mut writer = Writer::new();
    writer.write_group_header(12, 3);
    assert_eq!(writer.as_slice(), [12, 0, 3, 0]);

    let mut reader = Reader::new(writer.as_slice());
    assert_eq!(reader.read_group_header().unwrap(), (12, 3));
}

#[test]
fn encode_to_reuses_the_writer_allocation() {
    let message = Example {
        sequence: 99,
        active: Some(false),
        name: Some("magic"),
    };
    let expected = message.encode().unwrap();
    let mut writer = Writer::with_capacity(expected.len());

    message.encode_to(&mut writer).unwrap();
    assert_eq!(writer.as_slice(), expected);
    message.encode_to(&mut writer).unwrap();
    assert_eq!(writer.as_slice(), expected);
}

#[test]
fn benchmark_message_rejects_truncated_and_invalid_data() {
    let message = BenchmarkMessage {
        number: 42,
        signed: -7,
        active: true,
        name: "grid",
    };
    let encoded = message.encode().unwrap();

    for length in 0..encoded.len() {
        assert!(BenchmarkMessage::decode(&encoded[..length]).is_err());
    }

    let mut invalid_bool = encoded.clone();
    invalid_bool[HEADER_SIZE + 12] = 2;
    assert_eq!(
        BenchmarkMessage::decode(&invalid_bool),
        Err(Error::InvalidBool(2))
    );

    let mut invalid_utf8 = encoded;
    invalid_utf8[HEADER_SIZE + 14] = 255;
    assert_eq!(
        BenchmarkMessage::decode(&invalid_utf8),
        Err(Error::InvalidUtf8)
    );
}
