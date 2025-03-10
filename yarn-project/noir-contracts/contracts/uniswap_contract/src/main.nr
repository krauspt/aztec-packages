// docs:start:uniswap_setup
mod interfaces;
mod util;

// Demonstrates how to use portal contracts to swap on L1 Uniswap with funds on L2
// Has two separate flows for private and public respectively
// Uses the token bridge contract, which tells which input token we need to talk to and handles the exit funds to L1 
contract Uniswap {
    use dep::aztec::protocol_types::{
        abis::function_selector::FunctionSelector,
        address::{
            AztecAddress,
            EthAddress,
        },
    };
    use dep::aztec::{
        oracle::{context::get_portal_address},
        state_vars::{map::Map, public_state::PublicState},
    };

    use dep::authwit::auth::{IS_VALID_SELECTOR, assert_current_call_valid_authwit_public, compute_authwit_message_hash};

    use crate::interfaces::{Token, TokenBridge};
    use crate::util::{compute_swap_private_content_hash, compute_swap_public_content_hash};

    struct Storage {
        // like with account contracts, stores the approval message on a slot and tracks if they are active
        approved_action: Map<Field, PublicState<bool>>,
        // tracks the nonce used to create the approval message for burning funds
        // gets incremented each time after use to prevent replay attacks
        nonce_for_burn_approval: PublicState<Field>,
    }

    #[aztec(private)]
    fn constructor() {}
    // docs:end:uniswap_setup

    // docs:start:swap_public
    #[aztec(public)]
    fn swap_public(
        sender: AztecAddress,
        input_asset_bridge: AztecAddress,
        input_amount: Field,
        output_asset_bridge: AztecAddress,
        // params for using the transfer approval
        nonce_for_transfer_approval: Field,
        // params for the swap
        uniswap_fee_tier: Field,
        minimum_output_amount: Field,
        // params for the depositing output_asset back to Aztec
        recipient: AztecAddress,
        secret_hash_for_L1_to_l2_message: Field,
        deadline_for_L1_to_l2_message: Field,
        canceller_for_L1_to_L2_message: EthAddress,
        caller_on_L1: EthAddress,
        // nonce for someone to call swap on sender's behalf
        nonce_for_swap_approval: Field
    ) {
        if (!sender.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, sender);
        }

        let input_asset = TokenBridge::at(input_asset_bridge).token(context);

        // Transfer funds to this contract
        Token::at(input_asset).transfer_public(
            context,
            sender,
            context.this_address(),
            input_amount,
            nonce_for_transfer_approval
        );

        // Approve bridge to burn this contract's funds and exit to L1 Uniswap Portal
        let _void = context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_approve_bridge_and_exit_input_asset_to_L1((Field),(Field),Field)"),
            [input_asset.to_field(), input_asset_bridge.to_field(), input_amount]
        );

        // Create swap message and send to Outbox for Uniswap Portal
        // this ensures the integrity of what the user originally intends to do on L1.
        let input_asset_bridge_portal_address = get_portal_address(input_asset_bridge);
        let output_asset_bridge_portal_address = get_portal_address(output_asset_bridge);
        // ensure portal exists - else funds might be lost
        assert(
            !input_asset_bridge_portal_address.is_zero(), "L1 portal address of input_asset's bridge is 0"
        );
        assert(
            !output_asset_bridge_portal_address.is_zero(), "L1 portal address of output_asset's bridge is 0"
        );

        let content_hash = compute_swap_public_content_hash(
            input_asset_bridge_portal_address,
            input_amount,
            uniswap_fee_tier,
            output_asset_bridge_portal_address,
            minimum_output_amount,
            recipient,
            secret_hash_for_L1_to_l2_message,
            deadline_for_L1_to_l2_message,
            canceller_for_L1_to_L2_message,
            caller_on_L1
        );
        context.message_portal(content_hash);
    }
    // docs:end:swap_public

    // docs:start:swap_private
    #[aztec(private)]
    fn swap_private(
        input_asset: AztecAddress, // since private, we pass here and later assert that this is as expected by input_bridge
        input_asset_bridge: AztecAddress,
        input_amount: Field,
        output_asset_bridge: AztecAddress,
        // params for using the unshield approval
        nonce_for_unshield_approval: Field,
        // params for the swap
        uniswap_fee_tier: Field,// which uniswap tier to use (eg 3000 for 0.3% fee)
        minimum_output_amount: Field, // minimum output amount to receive (slippage protection for the swap)
        // params for the depositing output_asset back to Aztec
        secret_hash_for_redeeming_minted_notes: Field,// secret hash used to redeem minted notes at a later time. This enables anyone to call this function and mint tokens to a user on their behalf
        secret_hash_for_L1_to_l2_message: Field, // for when l1 uniswap portal inserts the message to consume output assets on L2
        deadline_for_L1_to_l2_message: Field, // for when l1 uniswap portal inserts the message to consume output assets on L2
        canceller_for_L1_to_L2_message: EthAddress, // L1 address of who can cancel the message to consume assets on L2.
        caller_on_L1: EthAddress // ethereum address that can call this function on the L1 portal (0x0 if anyone can call)
    ) {
        // Assert that user provided token address is same as expected by token bridge.
        // we can't directly use `input_asset_bridge.token` because that is a public method and public can't return data to private
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_assert_token_is_same((Field),(Field))"),
            [input_asset.to_field(), input_asset_bridge.to_field()]
        );

        // Transfer funds to this contract
        Token::at(input_asset).unshield(
            &mut context,
            context.msg_sender(),
            context.this_address(),
            input_amount,
            nonce_for_unshield_approval
        );

        // Approve bridge to burn this contract's funds and exit to L1 Uniswap Portal
        context.call_public_function(
            context.this_address(),
            FunctionSelector::from_signature("_approve_bridge_and_exit_input_asset_to_L1((Field),(Field),Field)"),
            [input_asset.to_field(), input_asset_bridge.to_field(), input_amount]
        );

        // Create swap message and send to Outbox for Uniswap Portal
        // this ensures the integrity of what the user originally intends to do on L1.
        let input_asset_bridge_portal_address = get_portal_address(input_asset_bridge);
        let output_asset_bridge_portal_address = get_portal_address(output_asset_bridge);
        // ensure portal exists - else funds might be lost
        assert(
            !input_asset_bridge_portal_address.is_zero(), "L1 portal address of input_asset's bridge is 0"
        );
        assert(
            !output_asset_bridge_portal_address.is_zero(), "L1 portal address of output_asset's bridge is 0"
        );

        let content_hash = compute_swap_private_content_hash(
            input_asset_bridge_portal_address,
            input_amount,
            uniswap_fee_tier,
            output_asset_bridge_portal_address,
            minimum_output_amount,
            secret_hash_for_redeeming_minted_notes,
            secret_hash_for_L1_to_l2_message,
            deadline_for_L1_to_l2_message,
            canceller_for_L1_to_L2_message,
            caller_on_L1
        );
        context.message_portal(content_hash);
    }
    // docs:end:swap_private

    // docs:start:authwit_uniswap_get
    // Since the token bridge burns funds on behalf of this contract, this contract has to tell the token contract if the signature is valid
    // implementation is similar to how account contracts validate public approvals.
    // if valid, it returns the IS_VALID selector which is expected by token contract
    #[aztec(public)]
    fn is_valid_public(message_hash: Field) -> Field {
        let value = storage.approved_action.at(message_hash).read();
        if (value) { IS_VALID_SELECTOR } else { 0 }
    }
    // docs:end:authwit_uniswap_get

    // docs:start:authwit_uniswap_set
    // This helper method approves the bridge to burn this contract's funds and exits the input asset to L1
    // Assumes contract already has funds. 
    // Assume `token` relates to `token_bridge` (ie token_bridge.token == token)
    // Note that private can't read public return values so created an internal public that handles everything
    // this method is used for both private and public swaps.
    #[aztec(public)]
    internal fn _approve_bridge_and_exit_input_asset_to_L1(token: AztecAddress, token_bridge: AztecAddress, amount: Field) {
        // approve bridge to burn this contract's funds (required when exiting on L1, as it burns funds on L2):
        let nonce_for_burn_approval = storage.nonce_for_burn_approval.read();
        let selector = FunctionSelector::from_signature("burn_public((Field),Field,Field)");
        let message_hash = compute_authwit_message_hash(
            token_bridge,
            token,
            selector,
            [context.this_address().to_field(), amount, nonce_for_burn_approval]
        );
        storage.approved_action.at(message_hash).write(true);

        // increment nonce_for_burn_approval so it won't be used again
        storage.nonce_for_burn_approval.write(nonce_for_burn_approval + 1);

        // Exit to L1 Uniswap Portal !
        TokenBridge::at(token_bridge).exit_to_l1_public(
            context,
            context.this_portal_address(),
            amount,
            context.this_portal_address(),
            nonce_for_burn_approval
        );
    }
    // docs:end:authwit_uniswap_set

    // docs:start:assert_token_is_same
    #[aztec(public)]
    internal fn _assert_token_is_same(token: AztecAddress, token_bridge: AztecAddress) {
        assert(
            token.eq(TokenBridge::at(token_bridge).token(context)), "input_asset address is not the same as seen in the bridge contract"
        );
    }
    // docs:end:assert_token_is_same

    // /// Unconstrained /// 

    // this method exists solely for e2e tests to test that nonce gets incremented each time.
    unconstrained fn nonce_for_burn_approval() -> pub Field {
        storage.nonce_for_burn_approval.read()
    }

    // TODO: remove this placeholder once https://github.com/AztecProtocol/aztec-packages/issues/2918 is implemented
    unconstrained fn compute_note_hash_and_nullifier(
        contract_address: AztecAddress,
        nonce: Field,
        storage_slot: Field,
        serialized_note: [Field; 0]
    ) -> pub [Field; 4] {
        [0, 0, 0, 0]
    }
}
