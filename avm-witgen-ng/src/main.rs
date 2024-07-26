mod alu;
mod memory;
mod ranges;
mod value;

fn main() {
    println!("Starting witgen-ng...");

    let mut alu = alu::ALUChip::new();

    let addr_a = 0;
    let addr_b = 1;
    let addr_c = 2;

    alu.add(addr_a, addr_b, addr_c);
}
