use crate::{
    abis::{
        call_context::CallContext,
        side_effect::{SideEffect, SideEffectLinkedToNoteHash},
    },
    address::AztecAddress,
    constants::{
        MAX_NEW_L2_TO_L1_MSGS_PER_CALL,
        MAX_NEW_NULLIFIERS_PER_CALL,
        MAX_NEW_COMMITMENTS_PER_CALL,
        MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL,
        MAX_PUBLIC_DATA_READS_PER_CALL,
        MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL,
        NUM_FIELDS_PER_SHA256,
        RETURN_VALUES_LENGTH,
        GENERATOR_INDEX__PUBLIC_CIRCUIT_PUBLIC_INPUTS,
        PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH,
    },
    contrakt::{
        storage_read::StorageRead,
        storage_update_request::StorageUpdateRequest,
    },
    hash::pedersen_hash,
    header::Header,
    traits::{
        Hash,
        Serialize,
        Deserialize,
    },
    utils::reader::Reader,
};

struct PublicCircuitPublicInputs{
    call_context: CallContext,

    args_hash: Field,
    return_values: [Field; RETURN_VALUES_LENGTH],

    contract_storage_update_requests: [StorageUpdateRequest; MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL],
    contract_storage_reads: [StorageRead; MAX_PUBLIC_DATA_READS_PER_CALL],

    // todo: add sideeffect ranges for the input to these hashes
    public_call_stack_hashes: [Field; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL],
    new_commitments: [SideEffect; MAX_NEW_COMMITMENTS_PER_CALL],
    new_nullifiers: [SideEffectLinkedToNoteHash; MAX_NEW_NULLIFIERS_PER_CALL],
    new_l2_to_l1_msgs: [Field; MAX_NEW_L2_TO_L1_MSGS_PER_CALL],

    unencrypted_logs_hash: [Field; NUM_FIELDS_PER_SHA256],

    // Here so that the gas cost of this request can be measured by circuits, without actually needing to feed in the
    // variable-length data.
    unencrypted_log_preimages_length: Field,

    // Header of a block whose state is used during public execution. Set by sequencer to be a header of a block
    // previous to the one in which the tx is included.
    historical_header: Header,

    prover_address: AztecAddress,
}

impl Eq for PublicCircuitPublicInputs {
    fn eq(self, other: Self) -> bool {
        self.serialize() == other.serialize()
    }
}

impl Serialize<PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH> for PublicCircuitPublicInputs {
    fn serialize(self) -> [Field; PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH] {
        let mut fields: BoundedVec<Field, PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH> = BoundedVec::new(0); 
        fields.extend_from_array(self.call_context.serialize());   
        fields.push(self.args_hash);
        fields.extend_from_array(self.return_values);
        for i in 0..MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL {
            fields.extend_from_array(self.contract_storage_update_requests[i].serialize());
        }
        for i in 0..MAX_PUBLIC_DATA_READS_PER_CALL {
            fields.extend_from_array(self.contract_storage_reads[i].serialize());
        }
        fields.extend_from_array(self.public_call_stack_hashes);

        for i in 0..MAX_NEW_COMMITMENTS_PER_CALL{
            fields.extend_from_array(self.new_commitments[i].serialize());
        }
        for i in 0..MAX_NEW_NULLIFIERS_PER_CALL{
            fields.extend_from_array(self.new_nullifiers[i].serialize());
        }
        fields.extend_from_array(self.new_l2_to_l1_msgs);
        fields.extend_from_array(self.unencrypted_logs_hash);
        fields.push(self.unencrypted_log_preimages_length);
        fields.extend_from_array(self.historical_header.serialize());
        fields.push(self.prover_address.to_field());
        fields.storage
    }
}

impl Deserialize<PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH> for PublicCircuitPublicInputs {
    fn deserialize(serialized: [Field; PUBLIC_CIRCUIT_PUBLIC_INPUTS_LENGTH]) -> Self {
        // TODO(#4390): This should accept a reader ^ to avoid copying data.
        let mut reader = Reader::new(serialized);
        let inputs = PublicCircuitPublicInputs {
            call_context: reader.read_struct(CallContext::deserialize),
            args_hash: reader.read(),
            return_values: reader.read_array([0; RETURN_VALUES_LENGTH]),
            contract_storage_update_requests: reader.read_struct_array(StorageUpdateRequest::deserialize, [StorageUpdateRequest::empty(); MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL]),
            contract_storage_reads: reader.read_struct_array(StorageRead::deserialize, [StorageRead::empty(); MAX_PUBLIC_DATA_READS_PER_CALL]),
            public_call_stack_hashes: reader.read_array([0; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL]),
            new_commitments: reader.read_struct_array(SideEffect::deserialize, [SideEffect::empty(); MAX_NEW_COMMITMENTS_PER_CALL]),
            new_nullifiers: reader.read_struct_array(SideEffectLinkedToNoteHash::deserialize, [SideEffectLinkedToNoteHash::empty(); MAX_NEW_NULLIFIERS_PER_CALL]),
            new_l2_to_l1_msgs: reader.read_array([0; MAX_NEW_L2_TO_L1_MSGS_PER_CALL]),
            unencrypted_logs_hash: reader.read_array([0; NUM_FIELDS_PER_SHA256]),
            unencrypted_log_preimages_length: reader.read(),
            historical_header: reader.read_struct(Header::deserialize),
            prover_address: reader.read_struct(AztecAddress::deserialize),
        };

        reader.finish();
        inputs
    }
}

impl Hash for PublicCircuitPublicInputs {
    fn hash(self) -> Field {
        pedersen_hash(self.serialize(), GENERATOR_INDEX__PUBLIC_CIRCUIT_PUBLIC_INPUTS)
    }
}

#[test]
fn serialization_of_empty() {
    let pcpi: PublicCircuitPublicInputs = dep::std::unsafe::zeroed();
    let serialized = pcpi.serialize();
    let deserialized = PublicCircuitPublicInputs::deserialize(serialized);
    assert(pcpi.eq(deserialized));
}

#[test]
fn hash_smoke() {
    let pcpi: PublicCircuitPublicInputs = dep::std::unsafe::zeroed();
    let _hashed = pcpi.hash();
}
