---
title: Function Context
---

# The Function Context

## What is the context

The context is an object that is made available within every function in `Aztec.nr`. As mentioned in the [kernel circuit documentation](../../../../learn/concepts/circuits/kernels/private_kernel.md). At the beginning of a function's execution, the context contains all of the kernel information that application needs to execute. During the lifecycle of a transaction, the function will update the context with each of it's side effects (created notes, nullifiers etc.). At the end of a function's execution the mutated context is returned to the kernel to be checked for validity.

Behind the scenes, Aztec.nr will pass data the kernel needs to and from a circuit, this is abstracted away from the developer. In an developer's eyes; the context is a useful structure that allows access and mutate the state of the `Aztec` blockchain.

On this page, you'll learn

- The details and functionalities of the private context in Aztec.nr
- Difference between the private and public contexts and their unified APIs
- Components of the private context, such as inputs, block header, and contract deployment data
- Elements like return values, read requests, new commitments, and nullifiers in transaction processing
- Differences between the private and public contexts, especially the unique features and variables in the public context

## Two contexts, one API
The `Aztec` blockchain contains two environments [public and private](../../../../learn/concepts/hybrid_state/main.md). 

- Private, for private transactions taking place on user's devices.
- Public, for public transactions taking place on the network's sequencers.

As there are two distinct execution environments, they both require slightly differing execution contexts. Despite their differences; the API's for interacting with each are unified. Leading to minimal context switch when working between the two environments.

The following section will cover both contexts.

## The Private Context

The code snippet below shows what is contained within the private context.
#include_code private-context /yarn-project/aztec-nr/aztec/src/context/private_context.nr rust

### Private Context Broken Down

#### Inputs

The context inputs includes all of the information that is passed from the kernel circuit into the application circuit. It contains the following values.

#include_code private-context-inputs /yarn-project/aztec-nr/aztec/src/context/inputs/private_context_inputs.nr rust

As shown in the snippet, the application context is made up of 4 main structures. The call context, the block header, the contract deployment data and the private global variables.

First of all, the call context.

#include_code call-context /yarn-project/noir-protocol-circuits/src/crates/types/src/abis/call_context.nr rust

The call context contains information about the current call being made:

1. Msg Sender
   - The message sender is the account (Aztec Contract) that sent the message to the current context. In the first call of the kernel circuit (often the account contract call), this value will be empty. For all subsequent calls the value will be the previous call.

> The graphic below illustrates how the message sender changes throughout the kernel circuit iterations.

<img src="/img/context/sender_context_change.png" />

2. Storage contract address

   - This value is the address of the current context's contract address. This value will be the value of the current contract that is being executed except for when the current call is a delegate call (Warning: This is yet to be implemented). In this case the value will be that of the sending contract.

3. Portal Contract Address
   - This value stores the current contract's linked [portal contract](../portals/portals.md) address. As a quick recap, this value is the value of the contracts related ethereum l1 contract address, and will be the recipient of any messages that are created by this contract.
4. Flags
   - Furthermore there are a series of flags that are stored within the application context:
     - is_delegate_call: Denotes whether the current call is a delegate call. If true, then the storage contract address will be the address of the sender.
     - is_static_call: This will be set if and only if the current call is a static call. In a static call, state changing altering operations are not allowed.
     - is_contract_deployment: This will be set if and only if the current call is the contract's constructor.

### Header

Another structure that is contained within the context is the Header object.
In the private context this is a header of a block which used to generate proofs against.
In the public context this header is set by sequencer (sequencer executes public calls) and it is set to 1 block before the block in which the transaction is included.

#include_code header /yarn-project/noir-protocol-circuits/src/crates/types/src/header.nr rust

### Contract Deployment Data

Just like with the `is_contract_deployment` flag mentioned earlier. This data will only be set to true when the current transaction is one in which a contract is being deployed.

#include_code contract-deployment-data /yarn-project/noir-protocol-circuits/src/crates/types/src/contrakt/deployment_data.nr rust

### Private Global Variables

In the private execution context, we only have access to a subset of the total global variables, we are restricted to those which can be reliably proven by the kernel circuits.

#include_code private-global-variables /yarn-project/aztec-nr/aztec/src/context/globals/private_global_variables.nr rust

### Args Hash

To allow for flexibility in the number of arguments supported by Aztec functions, all function inputs are reduced to a singular value which can be proven from within the application.

The `args_hash` is the result of pedersen hashing all of a function's inputs.

### Return Values

The return values are a set of values that are returned from an applications execution to be passed to other functions through the kernel. Developers do not need to worry about passing their function return values to the `context` directly as `Aztec.nr` takes care of it for you. See the documentation surrounding `Aztec.nr` [macro expansion](./inner_workings.md#after-expansion) for more details.

    return_values : BoundedVec<Field, RETURN_VALUES_LENGTH>,

### Read Requests

<!-- TODO(maddiaa): leaving as todo until their is further clarification around their implementation in the protocol -->

### New Commitments

New commitments contains an array of all of the commitments created in the current execution context.

### New Nullifiers

New nullifiers contains an array of the new nullifiers emitted from the current execution context.

### Nullified Commitments

Nullified commitments is an optimization for introduced to help reduce state growth. There are often cases where commitments are created and nullified within the same transaction.  
In these cases there is no reason that these commitments should take up space on the node's commitment/nullifier trees. Keeping track of nullified commitments allows us to "cancel out" and prove these cases.

### Private Call Stack

The private call stack contains all of the external private function calls that have been created within the current context. Any function call objects are hashed and then pushed to the execution stack.
The kernel circuit will orchestrate dispatching the calls and returning the values to the current context.

### Public Call Stack

The public call stack contains all of the external function calls that are created within the current context. Like the private call stack above, the calls are hashed and pushed to this stack. Unlike the private call stack, these calls are not executed client side. Whenever the function is sent to the network, it will have the public call stack attached to it. At this point the sequencer will take over and execute the transactions.

### New L2 to L1 msgs

New L2 to L1 messages contains messages that are delivered to the [l1 outbox](../../../../learn/concepts/communication/cross_chain_calls.md) on the execution of each rollup.

## Public Context

The Public Context includes all of the information passed from the `Public VM` into the execution environment. It is very similar to the [Private Context](#the-private-context), however it has some minor differences (detailed below).

### Public Context Inputs

In the current version of the system, the public context is almost a clone of the private execution context. It contains the same call context data, access to the same historical tree roots, however it does NOT have access to contract deployment data, this is due to traditional contract deployments only currently being possible from private transactions.

#include_code public-context-inputs /yarn-project/aztec-nr/aztec/src/context/inputs/public_context_inputs.nr rust

### Public Global Variables

The public global variables are provided by the rollup sequencer and consequently contain some more values than the private global variables.

#include_code global-variables /yarn-project/noir-protocol-circuits/src/crates/types/src/abis/global_variables.nr rust
