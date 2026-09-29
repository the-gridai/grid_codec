use criterion::{black_box, criterion_group, criterion_main, Criterion};
use grid_codec::{benchmark_message, BenchmarkMessage, Decode, Encode};

const NUMBER: u32 = 42;
const SIGNED: i64 = -7;
const ACTIVE: bool = true;
const NAME: &str = "grid";

fn benchmark(c: &mut Criterion) {
    let message = BenchmarkMessage {
        number: NUMBER,
        signed: SIGNED,
        active: ACTIVE,
        name: NAME,
    };
    let binary = message.encode().expect("benchmark fixture must encode");

    c.bench_function("pure_rust/field_access", |b| {
        b.iter(|| benchmark_message::get_number(black_box(&binary)).unwrap())
    });
    c.bench_function("pure_rust/encode", |b| {
        b.iter(|| black_box(&message).encode().unwrap())
    });
    c.bench_function("pure_rust/decode", |b| {
        b.iter(|| BenchmarkMessage::decode(black_box(&binary)).unwrap())
    });
}

criterion_group!(benches, benchmark);
criterion_main!(benches);
