use grid_codec::{benchmark_message, BenchmarkMessage, Decode, Encode, Header, Reader};
use rustler::{Binary, Env, NewBinary, NifResult};

#[derive(rustler::NifStruct)]
#[module = "GridCodec.Native.Header"]
struct HeaderTerm {
    block_length: u16,
    template_id: u16,
    schema_id: u16,
    version: u16,
}

fn nif_error(error: impl ToString) -> rustler::Error {
    rustler::Error::Term(Box::new(error.to_string()))
}

fn binary_from_bytes<'a>(env: Env<'a>, bytes: &[u8]) -> Binary<'a> {
    let mut output = NewBinary::new(env, bytes.len());
    output.as_mut_slice().copy_from_slice(bytes);
    output.into()
}

#[rustler::nif]
fn read_header(binary: Binary<'_>) -> NifResult<HeaderTerm> {
    let (header, _) = Header::decode(binary.as_slice()).map_err(nif_error)?;
    Ok(HeaderTerm {
        block_length: header.block_length,
        template_id: header.template_id,
        schema_id: header.schema_id,
        version: header.version,
    })
}

#[rustler::nif]
fn benchmark_get_number(binary: Binary<'_>) -> NifResult<u32> {
    benchmark_message::get_number(binary.as_slice()).map_err(nif_error)
}

#[rustler::nif]
fn benchmark_encode<'a>(
    env: Env<'a>,
    number: u32,
    signed: i64,
    active: bool,
    name: String,
) -> NifResult<Binary<'a>> {
    let message = BenchmarkMessage {
        number,
        signed,
        active,
        name: &name,
    };
    let encoded_len = message.encoded_len().map_err(nif_error)?;
    let mut output = NewBinary::new(env, encoded_len);
    Encode::encode_into(&message, output.as_mut_slice()).map_err(nif_error)?;
    Ok(output.into())
}

#[rustler::nif]
fn benchmark_decode(binary: Binary<'_>) -> NifResult<(u32, i64, bool, String)> {
    let message = BenchmarkMessage::decode(binary.as_slice()).map_err(nif_error)?;
    Ok((
        message.number,
        message.signed,
        message.active,
        message.name.to_owned(),
    ))
}

// Kept for compatibility with the initial bridge API.
#[rustler::nif]
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
    writer.write_string8(Some(&name)).map_err(nif_error)?;
    Ok(binary_from_bytes(env, writer.as_slice()))
}

#[rustler::nif]
fn decode_primitives(binary: Binary<'_>) -> NifResult<(u32, i64, bool, String)> {
    let mut reader = Reader::new(binary.as_slice());
    let number = reader.read_u32().map_err(nif_error)?;
    let signed = reader.read_i64().map_err(nif_error)?;
    let active = reader
        .read_bool()
        .map_err(nif_error)?
        .ok_or_else(|| nif_error("boolean is null"))?;
    let name = reader
        .read_string8()
        .map_err(nif_error)?
        .unwrap_or_default()
        .to_owned();
    Ok((number, signed, active, name))
}

rustler::init!("Elixir.GridCodec.Native.Nif");
