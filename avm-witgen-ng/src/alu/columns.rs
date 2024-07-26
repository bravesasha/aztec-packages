use crate::memory::MemoryValue;

pub enum ALUColumn {
    ColA(MemoryValue),
    ColB(MemoryValue),
    ColC(MemoryValue),
}

impl ALUColumn {
    pub fn A() -> ALUColumn {
        ALUColumn::ColA(MemoryValue::U0(0))
    }

    pub fn B() -> ALUColumn {
        ALUColumn::ColB(MemoryValue::U0(0))
    }

    pub fn C() -> ALUColumn {
        ALUColumn::ColC(MemoryValue::U0(0))
    }

    pub fn value(&self) -> &MemoryValue {
        match self {
            ALUColumn::ColA(value) => value,
            ALUColumn::ColB(value) => value,
            ALUColumn::ColC(value) => value,
        }
    }

    pub fn value_mut(&mut self) -> &mut MemoryValue {
        match self {
            ALUColumn::ColA(value) => value,
            ALUColumn::ColB(value) => value,
            ALUColumn::ColC(value) => value,
        }
    }
}

// impl<'a> TryInto<&'a MemoryValue> for ALUColumn {
//     type Error = &'static str;

//     fn try_into(self) -> Result<&'a MemoryValue, Self::Error> {
//         Ok(self.value())
//     }
// }
