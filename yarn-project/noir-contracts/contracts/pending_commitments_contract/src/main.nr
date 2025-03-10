// Test contract to confirm that notes can be inserted and then later
// read (eventually even nullified) in the same TX. This contract
// also contains some "bad" test cases to ensure that notes cannot
// be read/nullified before their creation etc.
contract PendingCommitments {
    // Libs
    use dep::std::option::Option;
    use dep::value_note::{
        balance_utils,
        filter::filter_notes_min_sum,
        value_note::{VALUE_NOTE_LEN, ValueNote},
    };
    use dep::aztec::{
        context::{PrivateContext, PublicContext, Context},
        log::emit_encrypted_log,
        note::{
            note_getter::NoteGetterOptions,
            note_header::NoteHeader,
            utils as note_utils,
        },
        state_vars::{map::Map, set::Set},
    };
    use dep::aztec::protocol_types::{
        address::AztecAddress,
        abis::function_selector::FunctionSelector,
    };

    struct Storage {
        balances: Map<AztecAddress, Set<ValueNote>>,
    }

    // TODO(dbanks12): consolidate code into internal helper functions
    // (once Noir's support for this is more robust)

    #[aztec(private)]
    fn constructor() {}

    // Confirm can access pending commitments by creating / inserting a note and then
    // getting / reading that note all in the same contract function
    // Realistic way to describe this test is "Mint note A, then burn note A in the same transaction"
    #[aztec(private)]
    fn test_insert_then_get_then_nullify_flat(amount: Field, owner: AztecAddress) -> Field {
        let owner_balance = storage.balances.at(owner);
        let mut note = ValueNote::new(amount, owner);

        // Insert note
        owner_balance.insert(&mut note, true);

        let options = NoteGetterOptions::with_filter(filter_notes_min_sum, amount);
        // get note inserted above
        let maybe_notes = owner_balance.get_notes(options);

        let note0 = maybe_notes[0].unwrap();
        assert(note.value == note0.value);
        assert(maybe_notes[1].is_none());

        owner_balance.remove(note0);

        note0.value
    }

    // Confirm cannot access commitments inserted later in same function
    #[aztec(private)]
    fn test_bad_get_then_insert_flat(amount: Field, owner: AztecAddress) -> Field {
        let owner_balance = storage.balances.at(owner);

        let options = NoteGetterOptions::with_filter(filter_notes_min_sum, amount);
        // get note (note inserted at bottom of function shouldn't exist yet)
        let maybe_notes = owner_balance.get_notes(options);

        assert(maybe_notes[0].is_none());
        assert(maybe_notes[1].is_none());

        // Insert note
        let mut note = ValueNote::new(amount, owner);
        owner_balance.insert(&mut note, true);

        0
    }

    // Dummy nested/inner function (to pass a function which does nothing)
    #[aztec(private)]
    fn dummy(amount: Field, owner: AztecAddress) {}

    // Nested/inner function to create and insert a note
    #[aztec(private)]
    fn insert_note(amount: Field, owner: AztecAddress) {
        let owner_balance = storage.balances.at(owner);
        let mut note = ValueNote::new(amount, owner);

        // Insert note
        owner_balance.insert(&mut note, true);
    }

    // Nested/inner function to get a note and confirm it matches the expected value
    #[aztec(private)]
    fn get_then_nullify_note(expected_value: Field, owner: AztecAddress) -> Field {
        let owner_balance = storage.balances.at(owner);

        let options = NoteGetterOptions::new().set_limit(1);
        let note = owner_balance.get_notes(options)[0].unwrap();

        assert(expected_value == note.value);

        owner_balance.remove(note);

        expected_value
    }

    // Nested/inner function to get a note and confirms that none is returned
    #[aztec(private)]
    fn get_note_zero_balance(owner: AztecAddress) {
        let owner_balance = storage.balances.at(owner);

        let options = NoteGetterOptions::new();
        let maybe_notes = owner_balance.get_notes(options);

        assert(maybe_notes[0].is_none());
        assert(maybe_notes[1].is_none());
    }

    // Test pending commitments with note insertion done in a nested call
    // and "read" / get of that pending note/commitment in another nested call
    // Realistic way to describe this test is "Mint note A, then burn note A in the same transaction"
    #[aztec(private)]
    fn test_insert_then_get_then_nullify_all_in_nested_calls(
        amount: Field,
        owner: AztecAddress,
        insert_fn_selector: FunctionSelector,
        get_then_nullify_fn_selector: FunctionSelector,
        get_note_zero_fn_selector: FunctionSelector
    ) {
        // nested call to create/insert note
        let _callStackItem1 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            [amount, owner.to_field()]
        );
        // nested call to read and nullify that note
        let _callStackItem2 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            [amount, owner.to_field()]
        );
        // nested call to confirm that balance is zero
        let _callStackItem3 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_note_zero_fn_selector,
            [owner.to_field()]
        );
    }

    // same test as above, but insert 2, get 2, nullify 2
    #[aztec(private)]
    fn test_insert2_then_get2_then_nullify2_all_in_nested_calls(
        amount: Field,
        owner: AztecAddress,
        insert_fn_selector: FunctionSelector,
        get_then_nullify_fn_selector: FunctionSelector
    ) {
        // args for nested calls
        let args = [amount, owner.to_field()];

        // nested call to create/insert note
        let _callStackItem1 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            args
        );
        let _callStackItem2 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            args
        );
        // nested call to read and nullify that note
        let _callStackItem3 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            args
        );
        let _callStackItem4 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            args
        );
        // nested call to confirm that balance is zero
        // TODO(dbanks12): once > 4 nested calls is supported, can confirm 0 balance:
        //let _callStackItem5 = context.call_private_function(inputs.call_context.storage_contract_address, get_note_zero_fn_selector, [owner]);
    }

    // same test as above, but insert 2, get 1, nullify 1
    #[aztec(private)]
    fn test_insert2_then_get2_then_nullify1_all_in_nested_calls(
        amount: Field,
        owner: AztecAddress,
        insert_fn_selector: FunctionSelector,
        get_then_nullify_fn_selector: FunctionSelector
    ) {
        // args for nested calls
        let args = [amount, owner.to_field()];

        // nested call to create/insert note
        let _callStackItem1 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            args
        );
        let _callStackItem2 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            args
        );
        // nested call to read and nullify that note
        let _callStackItem3 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            args
        );
    }

    // insert 1 note, then get 2 notes (one pending, one persistent) and nullify both.
    // one nullifier will be squashed with the pending note, one will become persistent.
    // ONLY WORKS IF THERE IS A PERSISTENT NOTE TO GET
    #[aztec(private)]
    fn test_insert1_then_get2_then_nullify2_all_in_nested_calls(
        amount: Field,
        owner: AztecAddress,
        insert_fn_selector: FunctionSelector,
        get_then_nullify_fn_selector: FunctionSelector,
        get_note_zero_fn_selector: FunctionSelector
    ) {
        // args for nested calls
        let args = [amount, owner.to_field()];

        // nested call to create/insert note
        let _callStackItem1 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            insert_fn_selector,
            args
        );
        // nested call to read and nullify that note
        let _callStackItem2 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            args
        );
        let _callStackItem3 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_then_nullify_fn_selector,
            args
        );

        let _callStackItem4 = context.call_private_function(
            inputs.call_context.storage_contract_address,
            get_note_zero_fn_selector,
            [owner.to_field()]
        );
    }

    // Confirm cannot get/read a pending commitment in a nested call
    // that is created/inserted later in execution but in the parent.
    // NOTE: This test is especially important in an end-to-end context because the parent call
    // (and therefore the insertion) will be processed in an earlier kernel iteration, but the
    // nested call (later kernel iteration) should not be able to read the commitment despite
    // it being present at that stage in the kernel.
    // If we can somehow force the simulator to allow execution to succeed can ensure that this test fails in the kernel
    // #[aztec(private)]
    //fn test_bad_get_in_nested_call_then_insert(
    //    amount: Field,
    //    owner: AztecAddress,
    //    get_then_nullify_fn_selector: FunctionSelector,
    //) {
    //}

    // Computes note hash and nullifier.
    // Note 1: Needs to be defined by every contract producing logs.
    // Note 2: Having it in all the contracts gives us the ability to compute the note hash and nullifier differently for different kind of notes.
    unconstrained fn compute_note_hash_and_nullifier(
        contract_address: AztecAddress,
        nonce: Field,
        storage_slot: Field,
        serialized_note: [Field; VALUE_NOTE_LEN]
    ) -> pub [Field; 4] {
        let note_header = NoteHeader::new(contract_address, nonce, storage_slot);
        note_utils::compute_note_hash_and_nullifier(ValueNote::deserialize_content, note_header, serialized_note)
    }
}
