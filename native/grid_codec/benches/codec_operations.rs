use criterion::{black_box, criterion_group, criterion_main, Criterion};
use grid_codec::{
    benchmark_message, BenchmarkMessage, BenchmarkMessageView, Decode, Encode, Writer,
};

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
    let view = BenchmarkMessageView::new(&binary).unwrap();
    c.bench_function("pure_rust/validated_view_field_access", |b| {
        b.iter(|| black_box(view).number())
    });
    c.bench_function("pure_rust/encode", |b| {
        b.iter(|| black_box(&message).encode().unwrap())
    });
    let mut fixed_output = [0_u8; 64];
    c.bench_function("pure_rust/encode_into_slice", |b| {
        b.iter(|| {
            black_box(&message)
                .encode_into(black_box(&mut fixed_output))
                .unwrap()
        })
    });
    c.bench_function("pure_rust/general_encode_into_slice", |b| {
        b.iter(|| Encode::encode_into(black_box(&message), black_box(&mut fixed_output)).unwrap())
    });
    let mut writer = Writer::with_capacity(binary.len());
    c.bench_function("pure_rust/encode_reuse", |b| {
        b.iter(|| {
            black_box(&message)
                .encode_to(black_box(&mut writer))
                .unwrap()
        })
    });
    c.bench_function("pure_rust/decode", |b| {
        b.iter(|| BenchmarkMessage::decode(black_box(&binary)).unwrap())
    });
}

criterion_group!(benches, benchmark);
criterion_main!(benches);
