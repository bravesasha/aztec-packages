mod tail_to_public_output_hints;

use crate::components::{
    previous_kernel_validator::previous_kernel_validator_hints::PreviousKernelValidatorHints,
    tail_output_validator::{validate_value_transformation::{validate_transformed_values, validate_value_transformation}},
    tail_to_public_output_composer::meter_gas_used::{meter_gas_used_non_revertible, meter_gas_used_revertible},
    tail_to_public_output_validator::tail_to_public_output_hints::{generate_tail_to_public_output_hints, TailToPublicOutputHints}
};
use dep::types::{
    abis::{
    kernel_circuit_public_inputs::{PrivateKernelCircuitPublicInputs, PublicKernelCircuitPublicInputs},
    log_hash::{LogHash, ScopedEncryptedLogHash, NoteLogHash, ScopedLogHash}, note_hash::NoteHash,
    nullifier::Nullifier, public_call_request::PublicCallRequest
},
    address::AztecAddress,
    hash::{silo_encrypted_log_hash, silo_l2_to_l1_message, silo_note_hash, silo_nullifier},
    traits::{Empty, is_empty, is_empty_array},
    utils::arrays::{
    array_length, assert_split_sorted_transformed_value_arrays_asc,
    assert_split_sorted_transformed_value_arrays_desc, validate_array
}
};

struct TailToPublicOutputValidator {
    output: PublicKernelCircuitPublicInputs,
    previous_kernel: PrivateKernelCircuitPublicInputs,
    previous_kernel_hints: PreviousKernelValidatorHints,
    hints: TailToPublicOutputHints,
}

impl TailToPublicOutputValidator {
    pub fn new(
        output: PublicKernelCircuitPublicInputs,
        previous_kernel: PrivateKernelCircuitPublicInputs,
        previous_kernel_hints: PreviousKernelValidatorHints
    ) -> Self {
        let hints = generate_tail_to_public_output_hints(previous_kernel);
        TailToPublicOutputValidator { output, previous_kernel, previous_kernel_hints, hints }
    }

    pub fn validate<N>(self) {
        self.validate_empty_values();
        self.validate_propagated_values();
        self.validate_propagated_sorted_siloed_values();
        self.validate_gas_used();
    }

    fn validate_empty_values(self) {
        assert_eq(self.output.revert_code, 0, "revert_code must be empty");

        assert(
            is_empty_array(self.output.end_non_revertible.public_data_update_requests), "non-revertible public_data_update_requests must be empty"
        );
        assert(
            is_empty_array(self.output.end.public_data_update_requests), "revertible public_data_update_requests must be empty"
        );
    }

    fn validate_propagated_values(self) {
        assert_eq(self.output.constants, self.previous_kernel.constants, "mismatch constants");

        assert_eq(
            self.output.validation_requests.for_rollup, self.previous_kernel.validation_requests.for_rollup, "mismatch rollup_validation_requests"
        );

        assert_eq(self.output.fee_payer, self.previous_kernel.fee_payer, "mismatch fee_payer");

        // public_teardown_call_stack
        let num_teardown_calls = validate_array(self.output.public_teardown_call_stack);
        assert(
            (num_teardown_calls == 0) | (num_teardown_calls == 1), "invalid number of teardown call requests"
        );
        assert_eq(
            self.output.public_teardown_call_stack[0].item, self.previous_kernel.public_teardown_call_request.item, "mismatch public_teardown_call_request"
        );
        assert_eq(
            self.output.public_teardown_call_stack[0].counter, 0, "cannot expose teardown call request counter"
        );
    }

    fn validate_propagated_sorted_siloed_values(self) {
        let split_counter = self.previous_kernel.min_revertible_side_effect_counter;
        let prev_data = self.previous_kernel.end;
        let output_non_revertible = self.output.end_non_revertible;
        let output_revertible = self.output.end;
        let hints = self.hints;
        let previous_kernel_hints = self.previous_kernel_hints;

        // note_hashes
        let siloed_note_hashes = previous_kernel_hints.siloed_note_hashes;
        let unsiloed_note_hashes = prev_data.note_hashes;
        let tx_hash = output_non_revertible.nullifiers[0].value;
        let sorted_split_indexes = hints.sorted_note_hash_hints.sorted_indexes;
        let sorted_counters_gte = hints.sorted_note_hash_hints.sorted_counters_gte;
        let num_non_revertible = array_length(output_non_revertible.note_hashes);
        for i in 0..unsiloed_note_hashes.len() {
            let note_hash = unsiloed_note_hashes[i];
            let mut index = sorted_split_indexes[i];
            if sorted_counters_gte[index] == note_hash.counter() {
                index += num_non_revertible;
            }
            let siloed_note_hash = silo_note_hash(note_hash, tx_hash, index);
            assert_eq(siloed_note_hashes[i], siloed_note_hash, "mismatch siloed note hashes");
        }

        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.note_hashes,
            siloed_note_hashes.map(|value: Field| NoteHash { value, counter: 0 }.scope(AztecAddress::zero())),
            split_counter,
            output_non_revertible.note_hashes,
            output_revertible.note_hashes,
            hints.sorted_note_hash_hints
        );

        // nullifiers
        validate_value_transformation(
            prev_data.nullifiers,
            hints.siloed_nullifiers,
            |sn, n: Nullifier| (n.value == silo_nullifier(sn)) & (n.counter == 0) & (n.note_hash == 0)
        );
        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.nullifiers,
            hints.siloed_nullifiers,
            split_counter,
            output_non_revertible.nullifiers,
            output_revertible.nullifiers,
            hints.sorted_nullifier_hints
        );

        // l2_to_l1_msgs
        let tx_context = self.previous_kernel.constants.tx_context;
        validate_transformed_values(
            prev_data.l2_to_l1_msgs,
            hints.siloed_l2_to_l1_msgs,
            |msg| silo_l2_to_l1_message(msg, tx_context.version, tx_context.chain_id)
        );

        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.l2_to_l1_msgs,
            hints.siloed_l2_to_l1_msgs,
            split_counter,
            output_non_revertible.l2_to_l1_msgs,
            output_revertible.l2_to_l1_msgs,
            hints.sorted_l2_to_l1_msg_hints
        );

        // note_encrypted_logs_hashes
        validate_value_transformation(
            prev_data.note_encrypted_logs_hashes,
            hints.note_encrypted_logs_hashes,
            |nlh: NoteLogHash, lh: LogHash| (lh.value == nlh.value) & (lh.length == nlh.length) & (lh.counter == 0)
        );

        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.note_encrypted_logs_hashes,
            hints.note_encrypted_logs_hashes,
            split_counter,
            output_non_revertible.note_encrypted_logs_hashes,
            output_revertible.note_encrypted_logs_hashes,
            hints.sorted_note_encrypted_log_hash_hints
        );

        // encrypted_logs_hashes
        validate_value_transformation(
            prev_data.encrypted_logs_hashes,
            hints.siloed_encrypted_logs_hashes,
            |slh: ScopedEncryptedLogHash, lh: LogHash| (lh.value == silo_encrypted_log_hash(slh)) & (lh.length == slh.log_hash.length) & (lh.counter == 0)
        );

        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.encrypted_logs_hashes,
            hints.siloed_encrypted_logs_hashes,
            split_counter,
            output_non_revertible.encrypted_logs_hashes,
            output_revertible.encrypted_logs_hashes,
            hints.sorted_encrypted_log_hash_hints
        );

        // unencrypted_logs_hashes
        assert_split_sorted_transformed_value_arrays_asc(
            prev_data.unencrypted_logs_hashes,
            prev_data.unencrypted_logs_hashes.map(|log: ScopedLogHash| log.expose_to_public()),
            split_counter,
            output_non_revertible.unencrypted_logs_hashes,
            output_revertible.unencrypted_logs_hashes,
            hints.sorted_unencrypted_log_hash_hints
        );

        // public_data_update_requests
        let num_non_revertible_writes = validate_array(output_non_revertible.public_data_update_requests);
        assert_eq(num_non_revertible_writes, 0, "unexpected non-revertible public_data_update_requests");
        let num_revertible_writes = validate_array(output_revertible.public_data_update_requests);
        assert_eq(num_revertible_writes, 0, "unexpected revertible public_data_update_requests");

        // public_call_requests
        validate_value_transformation(
            prev_data.public_call_requests,
            hints.public_call_requests,
            |cr: PublicCallRequest, public_cr: PublicCallRequest| (public_cr.item == cr.item)
                & (public_cr.counter == 0)
        );

        assert_split_sorted_transformed_value_arrays_desc(
            prev_data.public_call_requests,
            hints.public_call_requests,
            split_counter,
            output_non_revertible.public_call_stack,
            output_revertible.public_call_stack,
            hints.sorted_public_call_request_hints
        )
    }

    fn validate_gas_used(self) {
        let gas_used = meter_gas_used_non_revertible(self.output.end_non_revertible);
        assert(
            self.output.end_non_revertible.gas_used == gas_used, "incorrect metered non-revertible gas used"
        );

        let gas_used = meter_gas_used_revertible(
            self.output.end,
            self.output.constants.tx_context.gas_settings.teardown_gas_limits
        );
        assert(self.output.end.gas_used == gas_used, "incorrect metered revertible gas used");

        let limits = self.previous_kernel.constants.tx_context.gas_settings.gas_limits;
        let total_gas_used = self.output.end_non_revertible.gas_used + self.output.end.gas_used;
        assert(total_gas_used.within(limits), "The gas used exceeds the gas limits");
    }
}
