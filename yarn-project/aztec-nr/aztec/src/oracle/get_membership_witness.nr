use dep::protocol_types::{
    constants::{
        ARCHIVE_HEIGHT,
        CONTRACT_TREE_HEIGHT,
        NOTE_HASH_TREE_HEIGHT,
    },
    utils::arr_copy_slice,
};

global CONTRACT_TREE_ID = 0;
global NOTE_HASH_TREE_ID = 2;
global ARCHIVE_TREE_ID = 5;

// Note: We have M here because we need to somehow set it when calling get_membership_witness function and one way to
// do it is to set M here and then set type of the return param, e.g.:
//
// `let witness: MembershipWitness<NOTE_HASH_TREE_HEIGHT, NOTE_HASH_TREE_HEIGHT + 1> = get_membership_witness(...);`
//
// Another way to do it would be to add "type_hint: [Field; T]" as argument to `get_membership_witness` but that's
// a bit too boilerplatey for my taste.
struct MembershipWitness<N, M> {
    index: Field,
    path: [Field; N],
}

#[oracle(getMembershipWitness)]
fn get_membership_witness_oracle<M>(_block_number: u32, _tree_id: Field, _leaf_value: Field) -> [Field; M] {}

unconstrained pub fn get_membership_witness<N, M>(block_number: u32, tree_id: Field, leaf_value: Field) -> MembershipWitness<N, M> {
    let fields: [Field; M] = get_membership_witness_oracle(block_number, tree_id, leaf_value);
    MembershipWitness { index: fields[0], path: arr_copy_slice(fields, [0; N], 1) }
}

unconstrained pub fn get_contract_membership_witness(
    block_number: u32,
    leaf_value: Field
) -> MembershipWitness<CONTRACT_TREE_HEIGHT, CONTRACT_TREE_HEIGHT + 1> {
    get_membership_witness(block_number, CONTRACT_TREE_ID, leaf_value)
}

// Note: get_nullifier_membership_witness function is implemented in get_nullifier_membership_witness.nr

unconstrained pub fn get_note_hash_membership_witness<N, M>(
    block_number: u32,
    leaf_value: Field
) -> MembershipWitness<NOTE_HASH_TREE_HEIGHT, NOTE_HASH_TREE_HEIGHT + 1> {
    get_membership_witness(block_number, NOTE_HASH_TREE_ID, leaf_value)
}

// There is no `get_public_data_membership_witness` function because it doesn't make sense to be getting a membership
// witness for a value in the public data tree.

unconstrained pub fn get_archive_membership_witness(
    block_number: u32,
    leaf_value: Field
) -> MembershipWitness<ARCHIVE_HEIGHT, ARCHIVE_HEIGHT + 1> {
    get_membership_witness(block_number, ARCHIVE_TREE_ID, leaf_value)
}
