use crate::alu::ALUColumn;
use crate::memory::MemoryChip;

pub struct ALUMemoryWrapper<'a> {
    memory: &'a mut MemoryChip,
}

impl ALUMemoryWrapper<'_> {
    pub fn new(memory: &mut MemoryChip) -> ALUMemoryWrapper {
        ALUMemoryWrapper { memory }
    }

    fn get_channel(column: &ALUColumn) -> u8 {
        match column {
            ALUColumn::ColA(_) => 0,
            ALUColumn::ColB(_) => 1,
            ALUColumn::ColC(_) => 2,
        }
    }

    pub fn read(&mut self, addr: u32, column: &mut ALUColumn) {
        let value = self.memory.read(addr, Self::get_channel(column));
        *column.value_mut() = *value;
    }

    pub fn write(&mut self, addr: u32, column: &ALUColumn) {
        self.memory.write(addr, Self::get_channel(column), column.value());
    }
}
