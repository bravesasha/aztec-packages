mod columns;
mod interactions;

use crate::memory::{MemoryChip, MemoryValue};

use columns::ALUColumn;
use interactions::ALUMemoryWrapper;

struct ALUEvent {
    clk: u64,
    opcode: u8,
    addr_a: u32,
    addr_b: u32,
    addr_c: u32,
    a: MemoryValue,
    b: MemoryValue,
    c: MemoryValue,
    error: bool,
}

pub struct ALUChip {
    events: Vec<ALUEvent>,
}

impl ALUChip {
    pub fn new() -> ALUChip {
        ALUChip { events: Vec::new() }
    }

    pub fn add(&mut self, addr_a: u32, addr_b: u32, addr_c: u32) {
        let mut memory_raw = MemoryChip::new();
        let mut memory = ALUMemoryWrapper::new(&mut memory_raw);

        let mut a = ALUColumn::A();
        let mut b = ALUColumn::B();
        let mut c = ALUColumn::C();

        memory.read(addr_a, &mut a);
        memory.read(addr_b, &mut b);

        // TODO: make this look nicer
        *c.value_mut() = (*a.value() + *b.value()).unwrap();

        memory.write(addr_c, &c);

        self.events.push(ALUEvent {
            clk: 0,
            opcode: 0, // ADD
            addr_a,
            addr_b,
            addr_c,
            a: *a.value(),
            b: *b.value(),
            c: *c.value(),
            error: false,
        });
    }

    pub fn lt(&mut self, addr_a: u32, addr_b: u32, addr_c: u32) {
        let mut memory_raw = MemoryChip::new();
        let mut memory = ALUMemoryWrapper::new(&mut memory_raw);

        let mut a = ALUColumn::A();
        let mut b = ALUColumn::B();
        let mut c = ALUColumn::C();

        memory.read(addr_a, &mut a);
        memory.read(addr_b, &mut b);

        // TODO: implement <
        let is_lt: bool = true;

        // TODO: make this look nicer
        *c.value_mut() = MemoryValue::U8(if is_lt { 1 } else { 0 });

        memory.write(addr_c, &c);

        self.events.push(ALUEvent {
            clk: 0,
            opcode: 0, // LT
            addr_a,
            addr_b,
            addr_c,
            a: *a.value(),
            b: *b.value(),
            c: *c.value(),
            error: false,
        });
    }
}
