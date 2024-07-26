use crate::value::ValueWithColumn;
use derive_more::{Add, Sub};
use std::collections::HashMap;

enum MemoryOp {
    Read,
    Write,
}

enum MemoryTag {
    U0,
    U1,
    U8,
    U16,
    U32,
    U64,
    U128,
    FF,
}

#[derive(Clone, Copy, Add, Sub)]
pub enum MemoryValue {
    U0(u8),
    U1(u8),
    U8(u8),
    U16(u16),
    U32(u32),
    U64(u64),
    U128(u128),
    FF(u64),
}

impl MemoryValue {
    pub fn tag(&self) -> MemoryTag {
        match self {
            MemoryValue::U0(_) => MemoryTag::U0,
            MemoryValue::U1(_) => MemoryTag::U1,
            MemoryValue::U8(_) => MemoryTag::U8,
            MemoryValue::U16(_) => MemoryTag::U16,
            MemoryValue::U32(_) => MemoryTag::U32,
            MemoryValue::U64(_) => MemoryTag::U64,
            MemoryValue::U128(_) => MemoryTag::U128,
            MemoryValue::FF(_) => MemoryTag::FF,
        }
    }
}

struct MemoryEvent {
    pub clk: u64,
    pub channel: u8,
    pub addr: u32,
    pub value: MemoryValue,
    pub operation: MemoryOp,
}

// struct ConcreteMemoryInteraction {}

// pub trait MemoryInteraction<const CHANNEL: u8> {
//     fn get_channel(&self) -> u8;
// }

// impl<const CHANNEL: u8> MemoryInteraction<CHANNEL> for ConcreteMemoryInteraction {
//     fn get_channel(&self) -> u8 {
//         CHANNEL
//     }
// }

pub struct MemoryChip {
    memory: HashMap<u32, MemoryValue>,
    // Events whose clock cycle ended.
    events: Vec<MemoryEvent>,
    // Events for the current clock cycle.
    staged_events: Vec<MemoryEvent>,
}

impl MemoryChip {
    pub fn new() -> MemoryChip {
        MemoryChip { memory: HashMap::new(), events: Vec::new(), staged_events: Vec::new() }
    }

    // pub fn int<const channel: u8>() -> impl MemoryInteraction<channel> {
    //     ConcreteMemoryInteraction::<channel & 1> {}
    // }

    pub fn read(&mut self, addr: u32, channel: u8) -> &MemoryValue {
        // range check address
        //// todo

        let value = match self.memory.get(&addr) {
            Some(value) => value,
            None => &MemoryValue::U0(0),
        };

        self.staged_events.push(MemoryEvent {
            clk: 0,
            channel: channel,
            addr: addr,
            value: *value,
            operation: MemoryOp::Read,
        });

        // self.lookup_counts.insert(dest.trace + ":" + dest.column, +1);
        value
    }

    pub fn write(&mut self, addr: u32, channel: u8, value: &MemoryValue) {
        // range check address
        //// todo
        // range check value
        // if not FF
        // ranges.assert_bitsize(whatever, c_val);

        self.memory.insert(addr, value.clone());

        self.staged_events.push(MemoryEvent {
            clk: 0,
            channel: channel,
            addr: addr,
            value: value.clone(),
            operation: MemoryOp::Write,
        });

        // self.lookup_counts.insert(value.trace + ":" + value.column, +1);
    }
}
