use dep::protocol_types::{
    constants::GENERATOR_INDEX__PUBLIC_LEAF_INDEX, hash::poseidon2_hash_with_separator,
    address::AztecAddress, header::Header, utils::field::full_field_less_than
};
use std::merkle::compute_merkle_root;

use crate::{context::PrivateContext, oracle::get_public_data_witness::get_public_data_witness};

trait PublicStorageHistoricalRead {
    fn public_storage_historical_read(header: Header, storage_slot: Field, contract_address: AztecAddress) -> Field;
}

impl PublicStorageHistoricalRead for Header { 
    fn public_storage_historical_read(self, storage_slot: Field, contract_address: AztecAddress) -> Field {
        // 1) Compute the leaf slot by siloing the storage slot with the contract address
        let public_data_tree_index = poseidon2_hash_with_separator(
            [contract_address.to_field(), storage_slot],
            GENERATOR_INDEX__PUBLIC_LEAF_INDEX
        );

        // 2) Get the membership witness of the slot
        let witness = get_public_data_witness(
            self.global_variables.block_number as u32,
            public_data_tree_index
        );

        // 3) Extract the value from the witness leaf and check that the storage slot is correct
        let preimage = witness.leaf_preimage;

        // Here we have two cases. Code based on same checks in `validate_public_data_reads` in `base_rollup_inputs`
        // 1. The value is the same as the one in the witness
        // 2. The value was never initialized and is zero
        let is_less_than_slot = full_field_less_than(preimage.slot, public_data_tree_index);
        let is_next_greater_than = full_field_less_than(public_data_tree_index, preimage.next_slot);
        let is_max = ((preimage.next_index == 0) & (preimage.next_slot == 0));
        let is_in_range = is_less_than_slot & (is_next_greater_than | is_max);

        let value = if is_in_range {
            0
        } else {
            assert_eq(preimage.slot, public_data_tree_index, "Public data tree index doesn't match witness");
            preimage.value
        };

        // 4) Prove that the leaf exists in the public data tree. Note that `hash` returns not just the hash of the value
        // but also the metadata (slot, next index and next slot).
        assert(
            self.state.partial.public_data_tree.root
            == compute_merkle_root(preimage.hash(), witness.index, witness.path), "Proving public value inclusion failed"
        );

        value
    }
}
