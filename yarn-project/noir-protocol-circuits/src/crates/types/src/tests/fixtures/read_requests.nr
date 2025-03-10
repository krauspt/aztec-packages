use crate::abis::{
    membership_witness::ReadRequestMembershipWitness,
    side_effect::SideEffect,
};
use crate::tests::fixtures;
use crate::constants::{
        MAX_READ_REQUESTS_PER_CALL,
};

pub fn generate_read_requests(how_many: Field) -> (BoundedVec<SideEffect, MAX_READ_REQUESTS_PER_CALL>, BoundedVec<ReadRequestMembershipWitness, MAX_READ_REQUESTS_PER_CALL>) {
    generate_read_requests_with_config(how_many, false, [0; MAX_READ_REQUESTS_PER_CALL])
}

pub fn generate_transient_read_requests(how_many: Field) -> (BoundedVec<SideEffect, MAX_READ_REQUESTS_PER_CALL>, BoundedVec<ReadRequestMembershipWitness, MAX_READ_REQUESTS_PER_CALL>) {
    generate_read_requests_with_config(how_many, true, [0; MAX_READ_REQUESTS_PER_CALL])
}

pub fn generate_read_requests_with_config(
    how_many: Field,
    is_transient: bool,
    hints_to_commitment: [Field; MAX_READ_REQUESTS_PER_CALL]
) -> (BoundedVec<SideEffect, MAX_READ_REQUESTS_PER_CALL>, BoundedVec<ReadRequestMembershipWitness, MAX_READ_REQUESTS_PER_CALL>) {
    let mut read_requests = BoundedVec::new(SideEffect::empty());
    let mut read_request_membership_witnesses = BoundedVec::new(dep::std::unsafe::zeroed());

    for i in 0..how_many {
        read_requests.push(SideEffect { value: i + 1, counter: 0 });
        let witness = ReadRequestMembershipWitness {
            leaf_index: i,
            sibling_path: fixtures::note_hash_tree::SIBLING_PATHS[i],
            is_transient,
            hint_to_commitment: hints_to_commitment[i]
        };
        read_request_membership_witnesses.push(witness);
    }

    (read_requests, read_request_membership_witnesses)
}
