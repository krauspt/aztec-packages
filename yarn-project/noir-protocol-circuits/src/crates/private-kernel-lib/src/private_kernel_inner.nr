use crate::common;
use dep::std::unsafe;
use dep::types::{
    abis::{
        previous_kernel_data::PreviousKernelData,
        private_kernel::private_call_data::PrivateCallData,
        kernel_circuit_public_inputs::{KernelCircuitPublicInputs, KernelCircuitPublicInputsBuilder},
        side_effect::{SideEffect, SideEffectLinkedToNoteHash},
    },
    mocked::verify_previous_kernel_state,
};

struct PrivateKernelInputsInner {
    previous_kernel: PreviousKernelData,
    private_call: PrivateCallData,
}

impl PrivateKernelInputsInner {
    fn pop_and_validate_this_private_call_hash(self, public_inputs: &mut KernelCircuitPublicInputsBuilder){
        let call_request = public_inputs.end.private_call_stack.pop();
        common::validate_call_against_request(self.private_call, call_request);
    }

    fn validate_contract_tree_root(self) {
        let purported_contract_tree_root = self.private_call.call_stack_item.public_inputs.historical_header.state.partial.contract_tree.root;
        let previous_kernel_contract_tree_root = self.previous_kernel.public_inputs.constants.historical_header.state.partial.contract_tree.root;

        assert(purported_contract_tree_root == previous_kernel_contract_tree_root, "purported_contract_tree_root does not match previous_kernel_contract_tree_root");
    }

    fn validate_inputs(self) {
        let this_call_stack_item = self.private_call.call_stack_item;
        let function_data = this_call_stack_item.function_data;
        assert(function_data.is_private, "Private kernel circuit can only execute a private function");
        assert(self.previous_kernel.public_inputs.is_private, "Can only verify a private kernel snark in the private kernel circuit");
    }

    pub fn native_private_kernel_circuit_inner(self) -> KernelCircuitPublicInputs {
        let mut public_inputs : KernelCircuitPublicInputsBuilder = unsafe::zeroed();
        public_inputs.is_private = true;

        common::validate_previous_kernel_values(self.previous_kernel.public_inputs.end);

        // Do this before any functions can modify the inputs.
        common::initialize_end_values(self.previous_kernel, &mut public_inputs);

        self.validate_inputs();

        common::validate_arrays(self.private_call.call_stack_item.public_inputs);

        self.pop_and_validate_this_private_call_hash(&mut public_inputs);

        common::validate_read_requests(
            public_inputs.constants.historical_header.state.partial.note_hash_tree.root,
            self.private_call.call_stack_item.public_inputs.read_requests,  // read requests from private call
            self.private_call.read_request_membership_witnesses);

        //TODO(David): feels like update_end_values should happen later
        common::update_end_values(self.private_call, &mut public_inputs);

        // ensure that historical/purported contract tree root matches the one in previous kernel
        self.validate_contract_tree_root();

        let this_call_stack_item = self.private_call.call_stack_item;

        common::contract_logic(self.private_call,
            &mut public_inputs,
            this_call_stack_item.public_inputs.contract_deployment_data,
            this_call_stack_item.function_data);

        let (is_previous_state_valid, updated_aggregation_object) = verify_previous_kernel_state(public_inputs.aggregation_object,self.private_call.proof);
        assert(is_previous_state_valid);

        public_inputs.aggregation_object = updated_aggregation_object;

        public_inputs.finish()
    }
}

mod tests {
    use crate::private_kernel_inner::PrivateKernelInputsInner;
    use dep::types::constants::{
        MAX_READ_REQUESTS_PER_CALL,
        MAX_NEW_COMMITMENTS_PER_TX,
    };
    use dep::types::{
        abis::{
            kernel_circuit_public_inputs::KernelCircuitPublicInputs,
            side_effect::{SideEffect, SideEffectLinkedToNoteHash},
        },
        tests::{
            previous_kernel_data_builder::PreviousKernelDataBuilder,
            private_call_data_builder::PrivateCallDataBuilder,
        },
        address::AztecAddress,
        hash::compute_logs_hash,
        utils::{
            arrays::array_length,
        },
    };

    struct PrivateKernelInnerInputsBuilder {
        previous_kernel: PreviousKernelDataBuilder,
        private_call: PrivateCallDataBuilder,
    }

    impl PrivateKernelInnerInputsBuilder {
        pub fn new() -> Self {
            let previous_kernel = PreviousKernelDataBuilder::new();
            let private_call = PrivateCallDataBuilder::new(false);

            PrivateKernelInnerInputsBuilder { previous_kernel, private_call }
        }

        pub fn is_delegate_call(&mut self) -> Self {
            let _ = self.private_call.is_delegate_call();
            *self
        }

        pub fn is_static_call(&mut self) -> Self {
            let _ = self.private_call.is_static_call();
            *self
        }

        pub fn is_internal_call(&mut self) -> Self {
            let _ = self.private_call.is_internal_call();
            self.previous_kernel.contract_address = self.private_call.contract_address;
            *self
        }

        pub fn execute(&mut self) -> KernelCircuitPublicInputs {
            let private_call = self.private_call.finish();
            // Update the previous_kernel's private_call_stack with the current call_stack_item.
            let hash = private_call.call_stack_item.hash();
            let is_delegate_call = private_call.call_stack_item.public_inputs.call_context.is_delegate_call;
            self.previous_kernel.push_private_call_request(hash, is_delegate_call);
            let previous_kernel = self.previous_kernel.finish();

            let kernel = PrivateKernelInputsInner {
                previous_kernel,
                private_call,
            };

            kernel.native_private_kernel_circuit_inner()
        }

        pub fn succeeded(&mut self) {
            let _ = self.execute();
        }

        pub fn failed(&mut self) {
            let _ = self.execute();
        }
    }

    #[test(should_fail_with = "contract address cannot be zero")]
    fn private_function_zero_storage_contract_address_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set (storage) contract_address to 0
        builder.private_call.contract_address = AztecAddress::zero();
        builder.private_call.public_inputs.call_context.storage_contract_address = AztecAddress::zero();

        builder.failed();
    }

    #[test(should_fail_with = "purported_contract_tree_root does not match previous_kernel_contract_tree_root")]
    fn private_function_incorrect_contract_tree_root_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set historical contract tree root to a wrong value (the correct value + 1).
        let contract_tree_root = builder.previous_kernel.historical_header.state.partial.contract_tree.root;
        builder.previous_kernel.historical_header.state.partial.contract_tree.root = contract_tree_root + 1;

        builder.failed();
    }

    #[test(should_fail_with="computed contract address does not match expected one")]
    fn private_function_incorrect_function_leaf_index_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set the leaf index of the function leaf to a wrong value (the correct value + 1).
        let leaf_index = builder.private_call.function_leaf_membership_witness.leaf_index;
        builder.private_call.function_leaf_membership_witness.leaf_index = leaf_index + 1;

        builder.failed();
    }

    #[test(should_fail_with="computed contract address does not match expected one")]
    fn private_function_incorrect_function_leaf_sibling_path_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set the first value of the sibling path to a wrong value (the correct value + 1).
        let sibling_path_0 = builder.private_call.function_leaf_membership_witness.sibling_path[0];
        builder.private_call.function_leaf_membership_witness.sibling_path[0] = sibling_path_0 + 1;

        builder.failed();
    }

    #[test(should_fail_with="computed contract address does not match expected one")]
    fn private_function_incorrect_contract_class_preimage_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();
        builder.private_call.contract_class_artifact_hash = builder.private_call.contract_class_artifact_hash + 1;
        builder.failed();
    }

    #[test(should_fail_with="computed contract address does not match expected one")]
    fn private_function_incorrect_partial_address_preimage_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();
        builder.private_call.salted_initialization_hash.inner = builder.private_call.salted_initialization_hash.inner + 1;
        builder.failed();
    }

    #[test(should_fail_with="computed contract address does not match expected one")]
    fn private_function_incorrect_address_preimage_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();
        builder.private_call.public_keys_hash.inner = builder.private_call.public_keys_hash.inner + 1;
        builder.failed();
    }

    #[test(should_fail_with = "calculated private_call_hash does not match provided private_call_hash at the top of the call stack")]
    fn private_function_incorrect_call_stack_item_hash_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        let private_call = builder.private_call.finish();
        let hash = private_call.call_stack_item.hash();
        // Set the first call stack hash to a wrong value (the correct hash + 1).
        builder.previous_kernel.push_private_call_request(hash + 1, false);
        let previous_kernel = builder.previous_kernel.finish();

        let kernel = PrivateKernelInputsInner { previous_kernel, private_call };

        let _ = kernel.native_private_kernel_circuit_inner();
    }

    #[test(should_fail_with="call stack msg_sender does not match caller contract address")]
    fn incorrect_msg_sender_for_regular_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set the msg_sender to a wrong value.
        builder.private_call.public_inputs.call_context.msg_sender.inner += 1;

        builder.failed();
    }

    #[test(should_fail_with="call stack storage address does not match expected contract address")]
    fn incorrect_storage_contract_for_regular_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Set the storage contract address to a wrong value.
        builder.private_call.public_inputs.call_context.storage_contract_address.inner += 1;

        builder.failed();
    }

    #[test]
    fn delegate_call_succeeds() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_delegate_call();
        builder.succeeded();
    }

    #[test(should_fail_with="caller context cannot be empty for delegate calls")]
    fn empty_caller_context_for_delegate_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_delegate_call();

        let private_call = builder.private_call.finish();
        let hash = private_call.call_stack_item.hash();
        // Caller context is empty for regular calls.
        let is_delegate_call = false;
        builder.previous_kernel.push_private_call_request(hash, is_delegate_call);
        let previous_kernel = builder.previous_kernel.finish();

        let kernel = PrivateKernelInputsInner { previous_kernel, private_call };

        let _ = kernel.native_private_kernel_circuit_inner();
    }

    #[test(should_fail_with="call stack msg_sender does not match expected msg_sender for delegate calls")]
    fn incorrect_msg_sender_for_delegate_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_delegate_call();

        // Set the msg_sender to be the caller contract.
        builder.private_call.public_inputs.call_context.msg_sender = builder.previous_kernel.contract_address;

        builder.failed();
    }

    #[test(should_fail_with="call stack storage address does not match expected contract address for delegate calls")]
    fn incorrect_storage_address_for_delegate_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_delegate_call();

        // Set the storage contract address to be the contract address.
        builder.private_call.public_inputs.call_context.storage_contract_address = builder.private_call.contract_address;

        builder.failed();
    }

    #[test(should_fail_with="curent contract address must not match storage contract address for delegate calls")]
    fn incorrect_storage_contract_for_delegate_calls_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_delegate_call();

        builder.private_call.contract_address = builder.private_call.public_inputs.call_context.storage_contract_address;

        builder.failed();
    }

    #[test]
    fn internal_call_succeeds() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_internal_call();
        builder.succeeded();
    }

    #[test(should_fail_with = "call is internal but msg_sender is not self")]
    fn private_function_incorrect_is_internal() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_internal_call();

        // Tweak the (storage) contract_address to be different to msg_sender.
        let msg_sender = builder.private_call.public_inputs.call_context.msg_sender.to_field();
        builder.private_call.contract_address = AztecAddress::from_field(msg_sender + 1);
        builder.private_call.public_inputs.call_context.storage_contract_address = AztecAddress::from_field(msg_sender + 1);

        builder.failed();
    }

    #[test]
    fn call_requests_succeeds() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_private_call_requests(2, false);
        builder.private_call.append_private_call_requests(1, true);
        builder.private_call.append_public_call_requests(1, false);
        builder.private_call.append_public_call_requests(2, true);

        builder.succeeded();
    }

    #[test(should_fail_with = "call requests length does not match the expected length")]
    fn incorrect_private_call_requests_length_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_private_call_requests(2, false);
        // Remove one call request.
        let _ = builder.private_call.private_call_stack.pop();

        builder.failed();
    }

    #[test(should_fail_with = "call requests length does not match the expected length")]
    fn incorrect_public_call_requests_length_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_public_call_requests(2, false);
        // Remove one call request.
        let _ = builder.private_call.public_call_stack.pop();

        builder.failed();
    }

    #[test(should_fail_with = "call stack hash does not match call request hash")]
    fn incorrect_private_call_request_hash_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_private_call_requests(2, false);
        let mut call_request = builder.private_call.private_call_stack.pop();
        // Change the hash to be a different value.
        call_request.hash += 1;
        builder.private_call.private_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "call stack hash does not match call request hash")]
    fn incorrect_public_call_request_hash_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_public_call_requests(2, false);
        let mut call_request = builder.private_call.public_call_stack.pop();
        // Change the hash to be a different value.
        call_request.hash += 1;
        builder.private_call.public_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "invalid caller")]
    fn incorrect_caller_address_for_private_call_request_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_private_call_requests(1, false);
        let mut call_request = builder.private_call.private_call_stack.pop();
        // Change the caller contract address to be a different value.
        call_request.caller_contract_address.inner += 1;
        builder.private_call.private_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "invalid caller")]
    fn incorrect_caller_address_for_public_call_request_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_public_call_requests(1, false);
        let mut call_request = builder.private_call.public_call_stack.pop();
        // Change the caller contract address to be a different value.
        call_request.caller_contract_address.inner += 1;
        builder.private_call.public_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "invalid caller")]
    fn incorrect_caller_context_for_private_delegate_call_request_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_private_call_requests(1, true);
        let mut call_request = builder.private_call.private_call_stack.pop();
        // Change the storage contract to be a different value.
        call_request.caller_context.storage_contract_address.inner += 1;
        builder.private_call.private_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "invalid caller")]
    fn incorrect_caller_context_for_public_delegate_call_request_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_public_call_requests(1, true);
        let mut call_request = builder.private_call.public_call_stack.pop();
        // Change the storage contract to be a different value.
        call_request.caller_context.storage_contract_address.inner += 1;
        builder.private_call.public_call_stack.push(call_request);

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_return_values() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.return_values.extend_from_array([0, 553]);

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_read_requests() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.read_requests.extend_from_array(
            [
            SideEffect { value: 0, counter: 0 },
            SideEffect { value: 9123, counter: 1 }
        ]
        );

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_commitments() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.new_commitments.extend_from_array(
            [
            SideEffect { value: 0, counter: 0 },
            SideEffect { value: 9123, counter: 1 }
        ]
        );

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_nullifiers() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.new_nullifiers.extend_from_array(
            [
            SideEffectLinkedToNoteHash { value: 0, note_hash: 0, counter: 0 },
            SideEffectLinkedToNoteHash { value: 12, note_hash: 0, counter: 1 }
        ]
        );

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_private_call_stack() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.private_call_stack_hashes.extend_from_array([0, 888]);

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_public_call_stack() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.public_call_stack_hashes.extend_from_array([0, 888]);

        builder.failed();
    }

    #[test(should_fail_with = "invalid array")]
    fn input_validation_malformed_arrays_new_l2_to_l1_msgs() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.public_inputs.new_l2_to_l1_msgs.extend_from_array([0, 888]);

        builder.failed();
    }

    #[test(should_fail_with = "extend_from_bounded_vec out of bounds")]
    fn private_kernel_should_fail_if_aggregating_too_many_commitments() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // The current call stack has 1 commitment;
        builder.private_call.public_inputs.new_commitments.push(SideEffect { value: 4321, counter: 0 });

        // Mock the previous new commitments to be full, therefore no more commitments can be added.
        let mut full_new_commitments = [SideEffect::empty(); MAX_NEW_COMMITMENTS_PER_TX];
        for i in 0..MAX_NEW_COMMITMENTS_PER_TX {
            full_new_commitments[i] = SideEffect {
                value: i + 1,
                counter: i as u32,
            };
        }
        builder.previous_kernel.end.new_commitments.extend_from_array(full_new_commitments);

        builder.failed();
    }

    #[test(should_fail_with="Private kernel circuit can only execute a private function")]
    fn private_function_is_private_false_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.function_data.is_private = false;

        builder.failed();
    }

    #[test(should_fail_with="Can only verify a private kernel snark in the private kernel circuit")]
    fn previous_kernel_is_private_false_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.previous_kernel.is_private = false;

        builder.failed();
    }

    #[test(should_fail_with="note hash tree root mismatch")]
    fn native_read_request_bad_request() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(2);

        // tweak read_request so it gives wrong root when paired with its sibling path
        let read_request = builder.private_call.public_inputs.read_requests.pop();
        builder.private_call.public_inputs.read_requests.push(SideEffect { value: read_request.value + 1, counter: read_request.counter });

        builder.failed();
    }

    #[test(should_fail_with="note hash tree root mismatch")]
    fn native_read_request_bad_leaf_index() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(2);

        // Tweak leaf index so it gives wrong root when paired with its request and sibling path.
        let mut read_request_membership_witness = builder.private_call.read_request_membership_witnesses.pop();
        read_request_membership_witness.leaf_index += 1;
        builder.private_call.read_request_membership_witnesses.push(read_request_membership_witness);

        builder.failed();
    }

    #[test(should_fail_with="note hash tree root mismatch")]
    fn native_read_request_bad_sibling_path() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(2);

        // Tweak the sibling path of the second read so it gives wrong root when paired with its request.
        let mut read_request_membership_witness = builder.private_call.read_request_membership_witnesses.pop();
        read_request_membership_witness.sibling_path[1] += 1;
        builder.private_call.read_request_membership_witnesses.push(read_request_membership_witness);

        builder.failed();
    }

    #[test(should_fail_with="note hash tree root mismatch")]
    fn native_read_request_root_mismatch() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(1);

        // Set the root to be a different root so the above read request is not under this root.
        let old_root = builder.previous_kernel.historical_header.state.partial.note_hash_tree.root;
        builder.previous_kernel.historical_header.state.partial.note_hash_tree.root = old_root + 1;

        builder.failed();
    }

    #[test]
    fn native_no_read_requests_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        assert_eq(builder.private_call.public_inputs.read_requests.len(), 0);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 0);
    }

    #[test]
    fn native_one_read_requests_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(1);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 0);
    }

    #[test]
    fn native_two_read_requests_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(2);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 0);
    }

    #[test]
    fn native_max_read_requests_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(MAX_READ_REQUESTS_PER_CALL);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 0);
    }

    #[test]
    fn native_one_transient_read_requests_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_transient_read_requests(1);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 1);
    }

    #[test]
    fn native_max_read_requests_one_transient_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_read_requests(1);
        builder.private_call.append_transient_read_requests(1);
        builder.private_call.append_read_requests(MAX_READ_REQUESTS_PER_CALL - 2);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), 1);
    }

    #[test]
    fn native_max_read_requests_all_transient_works() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.private_call.append_transient_read_requests(MAX_READ_REQUESTS_PER_CALL);

        let public_inputs = builder.execute();

        // non-transient read requests are NOT forwarded
        assert_eq(array_length(public_inputs.end.read_requests), MAX_READ_REQUESTS_PER_CALL);
    }

    #[test]
    fn native_logs_are_hashed_as_expected() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        // Logs for the current call stack.
        let encrypted_logs_hash = [16, 69];
        let encrypted_log_preimages_length = 100;
        let unencrypted_logs_hash = [26, 47];
        let unencrypted_log_preimages_length = 50;
        builder.private_call.set_encrypted_logs(encrypted_logs_hash, encrypted_log_preimages_length);
        builder.private_call.set_unencrypted_logs(unencrypted_logs_hash, unencrypted_log_preimages_length);

        // Logs for the previous call stack.
        let prev_encrypted_logs_hash = [80, 429];
        let prev_encrypted_log_preimages_length = 13;
        let prev_unencrypted_logs_hash = [956, 112];
        let prev_unencrypted_log_preimages_length = 24;
        builder.previous_kernel.set_encrypted_logs(prev_encrypted_logs_hash, prev_encrypted_log_preimages_length);
        builder.previous_kernel.set_unencrypted_logs(
            prev_unencrypted_logs_hash,
            prev_unencrypted_log_preimages_length
        );

        let public_inputs = builder.execute();

        assert_eq(
            public_inputs.end.encrypted_log_preimages_length, encrypted_log_preimages_length + prev_encrypted_log_preimages_length
        );
        assert_eq(
            public_inputs.end.unencrypted_log_preimages_length, unencrypted_log_preimages_length + prev_unencrypted_log_preimages_length
        );

        let expected_encrypted_logs_hash = compute_logs_hash(prev_encrypted_logs_hash, encrypted_logs_hash);
        assert_eq(public_inputs.end.encrypted_logs_hash, expected_encrypted_logs_hash);

        let expected_unencrypted_logs_hash = compute_logs_hash(prev_unencrypted_logs_hash, unencrypted_logs_hash);
        assert_eq(public_inputs.end.unencrypted_logs_hash, expected_unencrypted_logs_hash);
    }

    #[test(should_fail_with="new_commitments must be empty for static calls")]
    fn creating_new_commitments_on_static_call_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_static_call();

        builder.private_call.public_inputs.new_commitments.push(SideEffect { value: 1, counter: 0 });

        builder.failed();
    }

    #[test(should_fail_with="new_nullifiers must be empty for static calls")]
    fn creating_new_nullifiers_on_static_call_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new().is_static_call();

        builder.private_call.public_inputs.new_nullifiers.push(SideEffectLinkedToNoteHash { value: 1, note_hash: 0, counter: 0 });

        builder.failed();
    }

    #[test(should_fail_with="The 0th nullifier in the accumulated nullifier array is zero")]
    fn zero_0th_nullifier_fails() {
        let mut builder = PrivateKernelInnerInputsBuilder::new();

        builder.previous_kernel.end.new_nullifiers = BoundedVec::new(SideEffectLinkedToNoteHash::empty());

        builder.failed();
    }
}
