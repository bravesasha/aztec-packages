use dep::aztec::{
    protocol_types::{
    address::AztecAddress, traits::Empty, constants::GENERATOR_INDEX__NOTE_NULLIFIER,
    hash::poseidon2_hash_with_separator
},
    note::{note_header::NoteHeader, note_interface::NoteInterface, utils::compute_note_hash_for_consumption},
    oracle::unsafe_rand::unsafe_rand, keys::getters::get_nsk_app, context::PrivateContext
};

global ADDRESS_NOTE_LEN: Field = 3;
// ADDRESS_NOTE_LEN * 32 + 32(storage_slot as bytes) + 32(note_type_id as bytes)
global ADDRESS_NOTE_BYTES_LEN: Field = 3 * 32 + 64;

// docs:start:address_note_def
// Stores an address
#[aztec(note)]
struct AddressNote {
    address: AztecAddress,
    // The nullifying public key hash is used with the nsk_app to ensure that the note can be privately spent.
    npk_m_hash: Field,
    randomness: Field,
}

impl NoteInterface<ADDRESS_NOTE_LEN, ADDRESS_NOTE_BYTES_LEN> for AddressNote {

    fn compute_note_hash_and_nullifier(self, context: &mut PrivateContext) -> (Field, Field) {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = context.request_nsk_app(self.npk_m_hash);
        let nullifier = poseidon2_hash_with_separator([
            note_hash_for_nullify,
            secret
        ],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        );
        (note_hash_for_nullify, nullifier)
    }

    fn compute_note_hash_and_nullifier_without_context(self) -> (Field, Field) {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = get_nsk_app(self.npk_m_hash);
        let nullifier = poseidon2_hash_with_separator([
            note_hash_for_nullify,
            secret
        ],
            GENERATOR_INDEX__NOTE_NULLIFIER as Field,
        );
        (note_hash_for_nullify, nullifier)
    }
}

impl AddressNote {
    pub fn new(address: AztecAddress, npk_m_hash: Field) -> Self {
        let randomness = unsafe_rand();
        AddressNote { address, npk_m_hash, randomness, header: NoteHeader::empty() }
    }
    // docs:end:address_note_def
}
