use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion, Throughput};
use grid_codec::{Error, FixedBlockView, Header, Reader, Result};

const ORDER_BOOK_BLOCK_LENGTH: usize = 94;
const ORDER_BOOK_TEMPLATE_ID: u16 = 30;
const LIMIT_ORDER_BLOCK_LENGTH: usize = 786;
const LIMIT_ORDER_TEMPLATE_ID: u16 = 440;
const MARKET_PERIOD_BLOCK_LENGTH_V1: usize = 626;
const MARKET_PERIOD_TEMPLATE_ID: u16 = 35_333;
const SCHEMA_ID: u16 = 1;

type OrderBookStateUpdatedView<'a> =
    FixedBlockView<'a, ORDER_BOOK_BLOCK_LENGTH, SCHEMA_ID, ORDER_BOOK_TEMPLATE_ID>;
type LimitOrderSubmittedView<'a> =
    FixedBlockView<'a, LIMIT_ORDER_BLOCK_LENGTH, SCHEMA_ID, LIMIT_ORDER_TEMPLATE_ID>;
type MarketPeriodV1View<'a> =
    FixedBlockView<'a, MARKET_PERIOD_BLOCK_LENGTH_V1, SCHEMA_ID, MARKET_PERIOD_TEMPLATE_ID>;

fn copy_encoded(bytes: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(bytes.len());
    output.extend_from_slice(bytes);
    output
}

fn copy_encoded_into(bytes: &[u8], output: &mut [u8]) -> Result<usize> {
    if output.len() < bytes.len() {
        return Err(Error::InsufficientData {
            needed: bytes.len(),
            remaining: output.len(),
        });
    }
    output[..bytes.len()].copy_from_slice(bytes);
    Ok(bytes.len())
}

fn market_period_order_count(bytes: &[u8]) -> Result<u16> {
    let view = MarketPeriodV1View::new(bytes)?;
    let mut tail = view.tail();
    for group_index in 0..2 {
        let header = tail.get(..4).ok_or(Error::InsufficientData {
            needed: 4,
            remaining: tail.len(),
        })?;
        let block_length = usize::from(u16::from_le_bytes([header[0], header[1]]));
        let count = usize::from(u16::from_le_bytes([header[2], header[3]]));
        if group_index == 1 {
            return Ok(count as u16);
        }
        let group_len = 4 + block_length * count;
        tail = tail.get(group_len..).ok_or(Error::InsufficientData {
            needed: group_len,
            remaining: tail.len(),
        })?;
    }
    unreachable!()
}

const DIVERSE: &[u8] =
    include_bytes!("../fixtures/cortex/market_period_diverse_event_binaries.bin");
const SNAPSHOT: &[u8] = include_bytes!("../fixtures/cortex/market_period_v1_aggregate.bin");

fn diverse_events() -> Vec<&'static [u8]> {
    let count = u16::from_le_bytes([DIVERSE[0], DIVERSE[1]]) as usize;
    let mut offset = 2;
    let mut events = Vec::with_capacity(count);
    for _ in 0..count {
        let size = u32::from_le_bytes(DIVERSE[offset + 4..offset + 8].try_into().unwrap()) as usize;
        offset += 8;
        events.push(&DIVERSE[offset..offset + size]);
        offset += size;
    }
    events
}

fn benchmark(c: &mut Criterion) {
    let events = diverse_events();
    let order_book = events
        .iter()
        .copied()
        .find(|bytes| Header::decode(bytes).unwrap().0.template_id == 30)
        .unwrap();
    let limit_order = events
        .iter()
        .copied()
        .find(|bytes| Header::decode(bytes).unwrap().0.template_id == 440)
        .unwrap();

    let mut decode = c.benchmark_group("production_decode");
    decode.throughput(Throughput::Bytes(order_book.len() as u64));
    decode.bench_function("order_book/header_only", |b| {
        b.iter(|| Header::decode(black_box(order_book)).unwrap())
    });
    decode.bench_function("order_book/general_reader_u64", |b| {
        b.iter(|| {
            let mut reader = Reader::new(black_box(order_book));
            let header = reader.read_header().unwrap();
            reader.skip(78).unwrap();
            black_box((header, reader.read_u64().unwrap()))
        })
    });
    decode.bench_function("order_book/validated_fixed_view", |b| {
        b.iter(|| {
            let view = OrderBookStateUpdatedView::new(black_box(order_book)).unwrap();
            black_box((view.u32_at(52), view.u32_at(56), view.u64_at(78)))
        })
    });

    decode.throughput(Throughput::Bytes(limit_order.len() as u64));
    decode.bench_function("limit_order/validated_fixed_view", |b| {
        b.iter(|| {
            let view = LimitOrderSubmittedView::new(black_box(limit_order)).unwrap();
            black_box((
                view.u64_at(295),
                view.u64_at(303),
                view.u64_at(311),
                view.u64_at(319),
            ))
        })
    });

    decode.throughput(Throughput::Bytes(SNAPSHOT.len() as u64));
    decode.bench_function("market_period/validate_and_count_orders", |b| {
        b.iter(|| black_box(market_period_order_count(black_box(SNAPSHOT)).unwrap()))
    });
    decode.bench_function("market_period/validate_fixed_view", |b| {
        b.iter(|| {
            let view = MarketPeriodV1View::new(black_box(SNAPSHOT)).unwrap();
            black_box((view.u32_at(578), view.tail().len()))
        })
    });
    decode.finish();

    let mut encode = c.benchmark_group("production_encode");
    for (name, bytes) in [
        ("order_book", order_book),
        ("limit_order", limit_order),
        ("market_period", SNAPSHOT),
    ] {
        encode.throughput(Throughput::Bytes(bytes.len() as u64));
        encode.bench_function(format!("{name}/new_vec_copy"), |b| {
            b.iter(|| copy_encoded(black_box(bytes)))
        });
        encode.bench_function(format!("{name}/caller_slice_copy"), |b| {
            b.iter_batched_ref(
                || vec![0_u8; bytes.len()],
                |output| copy_encoded_into(black_box(bytes), black_box(output)).unwrap(),
                BatchSize::SmallInput,
            )
        });
    }
    encode.finish();
}

criterion_group!(benches, benchmark);
criterion_main!(benches);
