use crate::{
    abis::{
        call_context::CallContext,
        call_request::{CallerContext, CallRequest},
        combined_constant_data::CombinedConstantData,
        combined_accumulated_data::CombinedAccumulatedDataBuilder,
        kernel_circuit_public_inputs::KernelCircuitPublicInputs,
        previous_kernel_data::PreviousKernelData,
        public_data_read::PublicDataRead,
        public_data_update_request::PublicDataUpdateRequest,
        side_effect::{SideEffect, SideEffectLinkedToNoteHash},
    },
    address::{AztecAddress, EthAddress},
    header::Header,
    mocked::{AggregationObject, Proof, VerificationKey},
    tests::{
        fixtures,
        testing_harness::build_tx_context,
    },
    transaction::context::TxContext,
};
use crate::constants::{
        MAX_NEW_COMMITMENTS_PER_TX,
        MAX_NEW_NULLIFIERS_PER_TX,
        MAX_PUBLIC_DATA_READS_PER_TX,
        MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_TX,
        NUM_FIELDS_PER_SHA256,
        VK_TREE_HEIGHT,
};

struct PreviousKernelDataBuilder {
    contract_address: AztecAddress,
    portal_contract_address: EthAddress,
    end: CombinedAccumulatedDataBuilder,
    historical_header: Header,
    tx_context: TxContext,
    is_private: bool,
    proof: Proof,
    vk: VerificationKey,
    vk_index: u32,
    vk_path: [Field; VK_TREE_HEIGHT],
    sideffect_counter: u32,
}

impl PreviousKernelDataBuilder {
    pub fn new() -> Self {
        let mut end: CombinedAccumulatedDataBuilder = dep::std::unsafe::zeroed();
        end.new_nullifiers.push(SideEffectLinkedToNoteHash{
            value: 321,
            note_hash: 0,
            counter: 0
        }); // 0th nullifier must be non-zero.

        let tx_context = build_tx_context(false, 0);

        PreviousKernelDataBuilder {
            contract_address: fixtures::contracts::parent_contract.address,
            portal_contract_address: fixtures::contracts::parent_contract.portal_contract_address,
            end,
            historical_header: fixtures::HEADER,
            tx_context,
            is_private: true,
            proof: Proof {},
            vk: VerificationKey {},
            vk_index: 0,
            vk_path: [0; VK_TREE_HEIGHT],
            sideffect_counter: 2,
        }
    }

    pub fn is_public(&mut self) -> Self {
        self.is_private = false;
        *self
    }

    pub fn append_public_data_update_requests(&mut self, num_updates: Field) {
        let value_offset = self.end.public_data_update_requests.len();
        for i in 0..MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_TX {
            if i as u64 < num_updates as u64 {
                let update_request = PublicDataUpdateRequest {
                    // The default leaf index is its index + 23.
                    leaf_slot: value_offset + i + 23,
                    // The default value is its index + 45.
                    old_value: value_offset + i + 45,
                    // The default value is its index + 678.
                    new_value: value_offset + i + 678,
                };
                self.end.public_data_update_requests.push(update_request);
            }
        }
    }

    pub fn append_public_data_read_requests(&mut self, num_reads: Field) {
        let value_offset = self.end.public_data_reads.len();
        for i in 0..MAX_PUBLIC_DATA_READS_PER_TX {
            if i as u64 < num_reads as u64 {
                let read_request = PublicDataRead {
                    // The default leaf index is its index + 34.
                    leaf_slot: value_offset + i + 34,
                    // The default value is its index + 5566.
                    value: value_offset + i + 5566,
                };
                self.end.public_data_reads.push(read_request);
            }
        }
    }

    fn next_sideffect_counter(&mut self) -> u32 {
        let counter = self.sideffect_counter;
        self.sideffect_counter += 1;
        counter
    }

    pub fn add_read_request_for_transient_commitment(&mut self, commitment_index: Field) -> Field {
        let new_read_request_index = self.end.read_requests.len();
        let commitment = self.end.new_commitments.get(commitment_index);
        let read_request = SideEffect {
            value: commitment.value,
            counter: self.next_sideffect_counter(),
        };
        self.end.read_requests.push(read_request);
        new_read_request_index
    }

    pub fn append_new_commitments(&mut self, num_new_commitments: Field) {
        let mocked_value_offset = self.end.new_commitments.len() + 1;
        for i in 0..MAX_NEW_COMMITMENTS_PER_TX {
            if i as u64 < num_new_commitments as u64 {
                // The default value is its index + 1.
                self.end.new_commitments.push(SideEffect{
                    value: i + mocked_value_offset,
                    counter: self.next_sideffect_counter()
                });
            }
        }
    }

    pub fn append_new_nullifiers(&mut self, num_extra_nullifier: Field) {
        let first_nullifier = self.end.new_nullifiers.get(0);
        let mocked_value_offset = first_nullifier.value + self.end.new_nullifiers.len();
        for i in 1..MAX_NEW_NULLIFIERS_PER_TX {
            if i as u64 <= num_extra_nullifier as u64 {
                // The default value is its index + the value of the first nullifier.
                self.end.new_nullifiers.push(SideEffectLinkedToNoteHash{
                    value: i + mocked_value_offset,
                    note_hash: first_nullifier.note_hash,
                    counter: self.next_sideffect_counter()
                });
            }
        }
    }

    pub fn set_encrypted_logs(&mut self, hash: [Field; NUM_FIELDS_PER_SHA256], preimages_length: Field) {
        self.end.encrypted_logs_hash = hash;
        self.end.encrypted_log_preimages_length = preimages_length;
    }

    pub fn set_unencrypted_logs(&mut self, hash: [Field; NUM_FIELDS_PER_SHA256], preimages_length: Field) {
        self.end.unencrypted_logs_hash = hash;
        self.end.unencrypted_log_preimages_length = preimages_length;
    }

    pub fn push_private_call_request(&mut self, hash: Field, is_delegate_call: bool) {
        let call_stack_item = self.generate_call_request(hash, is_delegate_call);
        self.end.private_call_stack.push(call_stack_item);
    }

    pub fn push_public_call_request(&mut self, hash: Field, is_delegate_call: bool) {
        let call_stack_item = self.generate_call_request(hash, is_delegate_call);
        self.end.public_call_stack.push(call_stack_item);
    }

    fn generate_call_request(&mut self, hash: Field, is_delegate_call: bool) -> CallRequest {
        let mut caller_context = CallerContext::empty();
        if is_delegate_call {
            caller_context.msg_sender = fixtures::MSG_SENDER;
            caller_context.storage_contract_address = self.contract_address;
        }
        let counter = self.next_sideffect_counter();
        let end_counter = counter + 10;
        self.sideffect_counter = end_counter;
        CallRequest {
            hash,
            caller_contract_address: self.contract_address,
            caller_context,
            start_side_effect_counter: counter,
            end_side_effect_counter: end_counter,
        }
    }

    pub fn finish(self) -> PreviousKernelData {
        let public_inputs = KernelCircuitPublicInputs {
            aggregation_object: AggregationObject {},
            meta_hwm: 0,
            end: self.end.finish(),
            constants: CombinedConstantData {
                historical_header: self.historical_header,
                tx_context: self.tx_context,
            },
            is_private: self.is_private,
        };
        PreviousKernelData {
            public_inputs,
            proof: self.proof,
            vk: self.vk,
            vk_index: self.vk_index,
            vk_path: self.vk_path,
        }
    }
}
