mod tail_output_hints;
mod validate_value_transformation;

use crate::components::{
    previous_kernel_validator::previous_kernel_validator_hints::PreviousKernelValidatorHints,
    tail_output_composer::meter_gas_used::meter_gas_used,
    tail_output_validator::{
    tail_output_hints::{generate_tail_output_hints, TailOutputHints},
    validate_value_transformation::{validate_transformed_values, validate_value_transformation}
}
};
use dep::types::{
    abis::{
    kernel_circuit_public_inputs::{KernelCircuitPublicInputs, PrivateKernelCircuitPublicInputs},
    log_hash::{LogHash, NoteLogHash, ScopedEncryptedLogHash, ScopedLogHash}
},
    hash::{
    compute_tx_logs_hash, compute_tx_note_logs_hash, silo_encrypted_log_hash, silo_l2_to_l1_message,
    silo_note_hash, silo_nullifier
},
    traits::is_empty,
    utils::arrays::{assert_sorted_transformed_value_array, assert_sorted_array_with_order_hints}
};

struct TailOutputValidator {
    output: KernelCircuitPublicInputs,
    previous_kernel: PrivateKernelCircuitPublicInputs,
    previous_kernel_hints: PreviousKernelValidatorHints,
    hints: TailOutputHints,
}

impl TailOutputValidator {
    pub fn new(
        output: KernelCircuitPublicInputs,
        previous_kernel: PrivateKernelCircuitPublicInputs,
        previous_kernel_hints: PreviousKernelValidatorHints
    ) -> Self {
        let hints = generate_tail_output_hints(previous_kernel);
        TailOutputValidator { output, previous_kernel, previous_kernel_hints, hints }
    }

    pub fn validate<N>(self) {
        self.validate_empty_values();
        self.validate_propagated_values();
        self.validate_propagated_sorted_siloed_values();
        self.validate_accumulated_values();
        self.validate_gas_used();
    }

    fn validate_empty_values(self) {
        assert(is_empty(self.output.start_state), "start_state must be empty");
        assert_eq(self.output.revert_code, 0, "revert_code must be empty");
    }

    fn validate_propagated_values(self) {
        assert_eq(self.output.constants, self.previous_kernel.constants, "mismatch constants");

        assert_eq(
            self.output.rollup_validation_requests, self.previous_kernel.validation_requests.for_rollup, "mismatch rollup_validation_requests"
        );

        assert_eq(self.output.fee_payer, self.previous_kernel.fee_payer, "mismatch fee_payer");
    }

    fn validate_propagated_sorted_siloed_values(self) {
        // note_hashes
        let siloed_note_hashes = self.previous_kernel_hints.siloed_note_hashes;
        let sorted_note_hash_hints = self.hints.sorted_note_hash_hints;
        let unsiloed_note_hashes = self.previous_kernel.end.note_hashes;
        let tx_hash = self.output.end.nullifiers[0]; // First nullifier is tx hash.
        for i in 0..unsiloed_note_hashes.len() {
            let siloed_note_hash = silo_note_hash(
                unsiloed_note_hashes[i],
                tx_hash,
                sorted_note_hash_hints[i].sorted_index
            );
            assert_eq(siloed_note_hashes[i], siloed_note_hash, "mismatch siloed note hashes");
        }

        assert_sorted_transformed_value_array(
            self.previous_kernel.end.note_hashes,
            siloed_note_hashes,
            self.output.end.note_hashes,
            sorted_note_hash_hints
        );

        // nullifiers
        validate_transformed_values(
            self.previous_kernel.end.nullifiers,
            self.hints.siloed_nullifiers,
            silo_nullifier
        );

        assert_sorted_transformed_value_array(
            self.previous_kernel.end.nullifiers,
            self.hints.siloed_nullifiers,
            self.output.end.nullifiers,
            self.hints.sorted_nullifier_hints
        );

        // l2_to_l1_msgs
        let tx_context = self.previous_kernel.constants.tx_context;
        validate_transformed_values(
            self.previous_kernel.end.l2_to_l1_msgs,
            self.hints.siloed_l2_to_l1_msgs,
            |msg| silo_l2_to_l1_message(msg, tx_context.version, tx_context.chain_id)
        );

        assert_sorted_transformed_value_array(
            self.previous_kernel.end.l2_to_l1_msgs,
            self.hints.siloed_l2_to_l1_msgs,
            self.output.end.l2_to_l1_msgs,
            self.hints.sorted_l2_to_l1_msg_hints
        );
    }

    fn validate_accumulated_values(self) {
        // note_encrypted_log_hashes
        validate_value_transformation(
            self.previous_kernel.end.note_encrypted_logs_hashes,
            self.hints.note_encrypted_log_hashes,
            |nlh: NoteLogHash, lh: LogHash| (nlh.value == lh.value) & (nlh.length == lh.length)
        );

        assert_sorted_transformed_value_array(
            self.previous_kernel.end.note_encrypted_logs_hashes,
            self.hints.note_encrypted_log_hashes,
            self.hints.sorted_note_encrypted_log_hashes,
            self.hints.sorted_note_encrypted_log_hash_hints
        );

        let hash = compute_tx_note_logs_hash(self.hints.sorted_note_encrypted_log_hashes);
        assert_eq(hash, self.output.end.note_encrypted_logs_hash, "mismatch note_encrypted_logs_hash");

        // encrypted_log_hashes
        validate_value_transformation(
            self.previous_kernel.end.encrypted_logs_hashes,
            self.hints.siloed_encrypted_log_hashes,
            |slh: ScopedEncryptedLogHash, lh: LogHash| (lh.value == silo_encrypted_log_hash(slh)) & (lh.length == slh.log_hash.length)
        );

        assert_sorted_transformed_value_array(
            self.previous_kernel.end.encrypted_logs_hashes,
            self.hints.siloed_encrypted_log_hashes,
            self.hints.sorted_siloed_encrypted_log_hashes,
            self.hints.sorted_encrypted_log_hash_hints
        );

        let hash = compute_tx_logs_hash(self.hints.sorted_siloed_encrypted_log_hashes);
        assert_eq(hash, self.output.end.encrypted_logs_hash, "mismatch encrypted_logs_hash");

        // unencrypted_log_hashes
        assert_sorted_array_with_order_hints(
            self.previous_kernel.end.unencrypted_logs_hashes,
            self.hints.sorted_unencrypted_log_hashes,
            self.hints.sorted_unencrypted_log_hash_hints
        );

        assert_eq(
            self.hints.sorted_unencrypted_log_hashes.map(|log: ScopedLogHash| log.expose_to_public()), self.output.end.unencrypted_logs_hashes, "mismatch unencrypted_logs_hashes"
        );
    }

    fn validate_gas_used(self) {
        let gas_used = meter_gas_used(
            self.output.end,
            self.output.constants.tx_context.gas_settings
        );
        assert(self.output.end.gas_used == gas_used, "incorrect metered gas used");

        let limits = self.previous_kernel.constants.tx_context.gas_settings.gas_limits;
        assert(self.output.end.gas_used.within(limits), "The gas used exceeds the gas limits");
    }
}
