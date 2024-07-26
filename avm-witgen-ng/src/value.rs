use crate::memory::MemoryValue;
pub trait Column {
    fn get_column(&self) -> String;
}

pub trait Trace {
    fn get_trace(&self) -> String;
}
pub trait ValueWithColumn {
    type T: Trace;
    type C: Column;
    fn get_value(&self) -> &MemoryValue;
    fn update_value(&mut self, value: MemoryValue);
}
