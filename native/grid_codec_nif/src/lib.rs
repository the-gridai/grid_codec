use grid_codec::{Header, Reader};
use rustler::{Binary, Env, NewBinary, NifResult};

#[derive(rustler::NifStruct)]
#[module = "GridCodec.Native.Header"]
struct HeaderTerm {
    block_length: u16,
    template_id: u16,
    schema_id: u16,
    version: u16,
}

#[rustler::nif(schedule = "DirtyCpu")]
fn read_header(binary: Binary<'_>) -> NifResult<HeaderTerm> {
    let (header, _) = Header::decode(binary.as_slice())
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?;
    Ok(HeaderTerm {
        block_length: header.block_length,
        template_id: header.template_id,
        schema_id: header.schema_id,
        version: header.version,
    })
}

#[rustler::nif(schedule = "DirtyCpu")]
fn encode_primitives<'a>(
    env: Env<'a>,
    number: u32,
    signed: i64,
    active: bool,
    name: String,
) -> NifResult<Binary<'a>> {
    let mut writer = grid_codec::Writer::with_capacity(15 + name.len());
    writer.write_u32(number);
    writer.write_i64(signed);
    writer.write_bool(Some(active));
    writer
        .write_string8(Some(&name))
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?;
    let bytes = writer.into_inner();
    let mut output = NewBinary::new(env, bytes.len());
    output.as_mut_slice().copy_from_slice(&bytes);
    Ok(output.into())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn decode_primitives(binary: Binary<'_>) -> NifResult<(u32, i64, bool, String)> {
    let mut reader = Reader::new(binary.as_slice());
    let number = reader
        .read_u32()
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?;
    let signed = reader
        .read_i64()
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?;
    let active = reader
        .read_bool()
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?
        .ok_or_else(|| rustler::Error::Term(Box::new("boolean is null")))?;
    let name = reader
        .read_string8()
        .map_err(|error| rustler::Error::Term(Box::new(error.to_string())))?
        .unwrap_or_default()
        .to_owned();
    Ok((number, signed, active, name))
}

rustler::init!("Elixir.GridCodec.Native.Nif");
