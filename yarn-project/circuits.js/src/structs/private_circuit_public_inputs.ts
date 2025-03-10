import { makeTuple } from '@aztec/foundation/array';
import { isArrayEmpty } from '@aztec/foundation/collection';
import { pedersenHash } from '@aztec/foundation/crypto';
import { Fr } from '@aztec/foundation/fields';
import { BufferReader, FieldReader, Tuple, serializeToBuffer, serializeToFields } from '@aztec/foundation/serialize';
import { FieldsOf } from '@aztec/foundation/types';

import {
  GeneratorIndex,
  MAX_NEW_COMMITMENTS_PER_CALL,
  MAX_NEW_L2_TO_L1_MSGS_PER_CALL,
  MAX_NEW_NULLIFIERS_PER_CALL,
  MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL,
  MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL,
  MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL,
  MAX_READ_REQUESTS_PER_CALL,
  NUM_FIELDS_PER_SHA256,
  RETURN_VALUES_LENGTH,
} from '../constants.gen.js';
import { ContractDeploymentData } from '../structs/contract_deployment_data.js';
import { Header } from '../structs/header.js';
import { SideEffect, SideEffectLinkedToNoteHash } from '../structs/side_effects.js';
import { CallContext } from './call_context.js';
import { NullifierKeyValidationRequest } from './nullifier_key_validation_request.js';

/**
 * Public inputs to a private circuit.
 * @see abis/private_circuit_public_inputs.hpp.
 */
export class PrivateCircuitPublicInputs {
  constructor(
    /**
     * Context of the call corresponding to this private circuit execution.
     */
    public callContext: CallContext,
    /**
     * Pedersen hash of function arguments.
     */
    public argsHash: Fr,
    /**
     * Return values of the corresponding function call.
     */
    public returnValues: Tuple<Fr, typeof RETURN_VALUES_LENGTH>,
    /**
     * The side-effect high watermark of the irrevertible part of the function call.
     */
    public metaHwm: Fr,
    /**
     * Read requests created by the corresponding function call.
     */
    public readRequests: Tuple<SideEffect, typeof MAX_READ_REQUESTS_PER_CALL>,
    /**
     * Nullifier key validation requests created by the corresponding function call.
     */
    public nullifierKeyValidationRequests: Tuple<
      NullifierKeyValidationRequest,
      typeof MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL
    >,
    /**
     * New commitments created by the corresponding function call.
     */
    public newCommitments: Tuple<SideEffect, typeof MAX_NEW_COMMITMENTS_PER_CALL>,
    /**
     * New nullifiers created by the corresponding function call.
     */
    public newNullifiers: Tuple<SideEffectLinkedToNoteHash, typeof MAX_NEW_NULLIFIERS_PER_CALL>,
    /**
     * Private call stack at the current kernel iteration.
     */
    public privateCallStackHashes: Tuple<Fr, typeof MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL>,
    /**
     * Public call stack at the current kernel iteration.
     */
    public publicCallStackHashes: Tuple<Fr, typeof MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL>,
    /**
     * New L2 to L1 messages created by the corresponding function call.
     */
    public newL2ToL1Msgs: Tuple<Fr, typeof MAX_NEW_L2_TO_L1_MSGS_PER_CALL>,
    /**
     * The end side effect counter for this call.
     */
    public endSideEffectCounter: Fr,
    /**
     * Hash of the encrypted logs emitted in this function call.
     * Note: Represented as an array of 2 fields in order to fit in all of the 256 bits of sha256 hash.
     */
    public encryptedLogsHash: Tuple<Fr, typeof NUM_FIELDS_PER_SHA256>,
    /**
     * Hash of the unencrypted logs emitted in this function call.
     * Note: Represented as an array of 2 fields in order to fit in all of the 256 bits of sha256 hash.
     */
    public unencryptedLogsHash: Tuple<Fr, typeof NUM_FIELDS_PER_SHA256>,
    /**
     * Length of the encrypted log preimages emitted in this function call.
     * Note: Here so that the gas cost of this request can be measured by circuits, without actually needing to feed
     *       in the variable-length data.
     */
    public encryptedLogPreimagesLength: Fr,
    /**
     * Length of the unencrypted log preimages emitted in this function call.
     */
    public unencryptedLogPreimagesLength: Fr,
    /**
     * Header of a block whose state is used during private execution (not the block the transaction is included in).
     */
    public historicalHeader: Header,
    /**
     * Deployment data of contracts being deployed in this kernel iteration.
     */
    public contractDeploymentData: ContractDeploymentData,
    /**
     * Chain Id of the instance.
     *
     * Note: The following 2 values are not redundant to the values in self.historical_header.global_variables because
     * they can be different in case of a protocol upgrade. In such a situation we could be using header from a block
     * before the upgrade took place but be using the updated protocol to execute and prove the transaction.
     */
    public chainId: Fr,
    /**
     * Version of the instance.
     */
    public version: Fr,
  ) {}

  /**
   * Create PrivateCircuitPublicInputs from a fields dictionary.
   * @param fields - The dictionary.
   * @returns A PrivateCircuitPublicInputs object.
   */
  static from(fields: FieldsOf<PrivateCircuitPublicInputs>): PrivateCircuitPublicInputs {
    return new PrivateCircuitPublicInputs(...PrivateCircuitPublicInputs.getFields(fields));
  }

  /**
   * Deserializes from a buffer or reader.
   * @param buffer - Buffer or reader to read from.
   * @returns The deserialized instance.
   */
  static fromBuffer(buffer: Buffer | BufferReader): PrivateCircuitPublicInputs {
    const reader = BufferReader.asReader(buffer);
    return new PrivateCircuitPublicInputs(
      reader.readObject(CallContext),
      reader.readObject(Fr),
      reader.readArray(RETURN_VALUES_LENGTH, Fr),
      reader.readObject(Fr),
      reader.readArray(MAX_READ_REQUESTS_PER_CALL, SideEffect),
      reader.readArray(MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL, NullifierKeyValidationRequest),
      reader.readArray(MAX_NEW_COMMITMENTS_PER_CALL, SideEffect),
      reader.readArray(MAX_NEW_NULLIFIERS_PER_CALL, SideEffectLinkedToNoteHash),
      reader.readArray(MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL, Fr),
      reader.readArray(MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL, Fr),
      reader.readArray(MAX_NEW_L2_TO_L1_MSGS_PER_CALL, Fr),
      reader.readObject(Fr),
      reader.readArray(NUM_FIELDS_PER_SHA256, Fr),
      reader.readArray(NUM_FIELDS_PER_SHA256, Fr),
      reader.readObject(Fr),
      reader.readObject(Fr),
      reader.readObject(Header),
      reader.readObject(ContractDeploymentData),
      reader.readObject(Fr),
      reader.readObject(Fr),
    );
  }

  static fromFields(fields: Fr[] | FieldReader): PrivateCircuitPublicInputs {
    const reader = FieldReader.asReader(fields);
    return new PrivateCircuitPublicInputs(
      reader.readObject(CallContext),
      reader.readField(),
      reader.readFieldArray(RETURN_VALUES_LENGTH),
      reader.readField(),
      reader.readArray(MAX_READ_REQUESTS_PER_CALL, SideEffect),
      reader.readArray(MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL, NullifierKeyValidationRequest),
      reader.readArray(MAX_NEW_COMMITMENTS_PER_CALL, SideEffect),
      reader.readArray(MAX_NEW_NULLIFIERS_PER_CALL, SideEffectLinkedToNoteHash),
      reader.readFieldArray(MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL),
      reader.readFieldArray(MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL),
      reader.readFieldArray(MAX_NEW_L2_TO_L1_MSGS_PER_CALL),
      reader.readField(),
      reader.readFieldArray(NUM_FIELDS_PER_SHA256),
      reader.readFieldArray(NUM_FIELDS_PER_SHA256),
      reader.readField(),
      reader.readField(),
      reader.readObject(Header),
      reader.readObject(ContractDeploymentData),
      reader.readField(),
      reader.readField(),
    );
  }

  /**
   * Create an empty PrivateCircuitPublicInputs.
   * @returns An empty PrivateCircuitPublicInputs object.
   */
  public static empty(): PrivateCircuitPublicInputs {
    return new PrivateCircuitPublicInputs(
      CallContext.empty(),
      Fr.ZERO,
      makeTuple(RETURN_VALUES_LENGTH, Fr.zero),
      Fr.ZERO,
      makeTuple(MAX_READ_REQUESTS_PER_CALL, SideEffect.empty),
      makeTuple(MAX_NULLIFIER_KEY_VALIDATION_REQUESTS_PER_CALL, NullifierKeyValidationRequest.empty),
      makeTuple(MAX_NEW_COMMITMENTS_PER_CALL, SideEffect.empty),
      makeTuple(MAX_NEW_NULLIFIERS_PER_CALL, SideEffectLinkedToNoteHash.empty),
      makeTuple(MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL, Fr.zero),
      makeTuple(MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL, Fr.zero),
      makeTuple(MAX_NEW_L2_TO_L1_MSGS_PER_CALL, Fr.zero),
      Fr.ZERO,
      makeTuple(NUM_FIELDS_PER_SHA256, Fr.zero),
      makeTuple(NUM_FIELDS_PER_SHA256, Fr.zero),
      Fr.ZERO,
      Fr.ZERO,
      Header.empty(),
      ContractDeploymentData.empty(),
      Fr.ZERO,
      Fr.ZERO,
    );
  }

  isEmpty() {
    // eslint-disable-next-line jsdoc/require-jsdoc
    const isEmptyArray = (arr: { isEmpty: (...args: any[]) => boolean }[]) => isArrayEmpty(arr, item => item.isEmpty());
    // eslint-disable-next-line jsdoc/require-jsdoc
    const isZeroArray = (arr: { isZero: (...args: any[]) => boolean }[]) => isArrayEmpty(arr, item => item.isZero());
    return (
      this.callContext.isEmpty() &&
      this.argsHash.isZero() &&
      isZeroArray(this.returnValues) &&
      this.metaHwm.isZero() &&
      isEmptyArray(this.readRequests) &&
      isEmptyArray(this.nullifierKeyValidationRequests) &&
      isEmptyArray(this.newCommitments) &&
      isEmptyArray(this.newNullifiers) &&
      isZeroArray(this.privateCallStackHashes) &&
      isZeroArray(this.publicCallStackHashes) &&
      isZeroArray(this.newL2ToL1Msgs) &&
      isZeroArray(this.encryptedLogsHash) &&
      isZeroArray(this.unencryptedLogsHash) &&
      this.encryptedLogPreimagesLength.isZero() &&
      this.unencryptedLogPreimagesLength.isZero() &&
      this.historicalHeader.isEmpty() &&
      this.contractDeploymentData.isEmpty() &&
      this.chainId.isZero() &&
      this.version.isZero()
    );
  }

  /**
   * Serialize into a field array. Low-level utility.
   * @param fields - Object with fields.
   * @returns The array.
   */
  static getFields(fields: FieldsOf<PrivateCircuitPublicInputs>) {
    return [
      fields.callContext,
      fields.argsHash,
      fields.returnValues,
      fields.metaHwm,
      fields.readRequests,
      fields.nullifierKeyValidationRequests,
      fields.newCommitments,
      fields.newNullifiers,
      fields.privateCallStackHashes,
      fields.publicCallStackHashes,
      fields.newL2ToL1Msgs,
      fields.endSideEffectCounter,
      fields.encryptedLogsHash,
      fields.unencryptedLogsHash,
      fields.encryptedLogPreimagesLength,
      fields.unencryptedLogPreimagesLength,
      fields.historicalHeader,
      fields.contractDeploymentData,
      fields.chainId,
      fields.version,
    ] as const;
  }

  /**
   * Serialize this as a buffer.
   * @returns The buffer.
   */
  toBuffer(): Buffer {
    return serializeToBuffer(...PrivateCircuitPublicInputs.getFields(this));
  }

  /**
   * Serialize this as a field array.
   */
  toFields(): Fr[] {
    return serializeToFields(...PrivateCircuitPublicInputs.getFields(this));
  }

  hash(): Fr {
    return Fr.fromBuffer(
      pedersenHash(
        this.toFields().map(field => field.toBuffer()),
        GeneratorIndex.PRIVATE_CIRCUIT_PUBLIC_INPUTS,
      ),
    );
  }
}
