use grid_codec::{FixedBlockView, Header};

const DIVERSE: &[u8] =
    include_bytes!("../fixtures/cortex/market_period_diverse_event_binaries.bin");
const SNAPSHOT: &[u8] = include_bytes!("../fixtures/cortex/market_period_v1_aggregate.bin");
type MarketPeriodV1View<'a> = FixedBlockView<'a, 626, 1, 35_333>;

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
    assert_eq!(offset, DIVERSE.len());
    events
}

#[test]
fn authentic_cortex_event_headers_parse_without_copying_payloads() {
    let events = diverse_events();
    assert_eq!(events.len(), 25);
    assert_eq!(
        events.iter().map(|event| event.len()).sum::<usize>(),
        18_111
    );
    for event in events {
        let (header, payload) = Header::decode(event).unwrap();
        assert_eq!(header.schema_id, 1);
        assert!(payload.len() >= usize::from(header.block_length));
    }
}

#[test]
fn authentic_market_period_snapshot_validates_as_a_borrowed_fixed_view() {
    let view = MarketPeriodV1View::new(SNAPSHOT).unwrap();
    assert_eq!(view.bytes().len(), 10_011);
    assert_eq!(view.fixed().len(), 626);
    assert_eq!(view.tail().len(), 9_377);
}

#[test]
fn authentic_market_period_snapshot_rejects_every_fixed_block_truncation() {
    for length in 0..(8 + 626) {
        assert!(MarketPeriodV1View::new(&SNAPSHOT[..length]).is_err());
    }
    assert!(MarketPeriodV1View::new(SNAPSHOT).is_ok());
}
