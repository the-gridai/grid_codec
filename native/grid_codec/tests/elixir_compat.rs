use grid_codec::{Header, Reader};

fn fixture(name: &str) -> Vec<u8> {
    let path = format!("{}/../../test/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    let contents = std::fs::read_to_string(path).unwrap();
    hex::decode(contents.trim()).unwrap()
}

#[test]
fn decodes_elixir_grid_codec_header_fixture() {
    let fixture = fixture("header.hex");
    let (header, rest) = Header::decode(&fixture).unwrap();
    assert_eq!(header, Header::new(32, 1, 100, 2));
    assert!(rest.is_empty());
}

#[test]
fn decodes_elixir_primitive_fixture() {
    let fixture = fixture("primitives.hex");
    let mut reader = Reader::new(&fixture);
    assert_eq!(reader.read_u32().unwrap(), 42);
    assert_eq!(reader.read_i64().unwrap(), -7);
    assert_eq!(reader.read_bool().unwrap(), Some(true));
    assert_eq!(reader.read_string8().unwrap(), Some("grid"));
    assert!(reader.remaining().is_empty());
}
