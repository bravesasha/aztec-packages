import { Tx, mockTx } from '@aztec/circuit-types';

import { expect } from '@jest/globals';

const verifyTx = (actual: Tx, expected: Tx) => {
  expect(actual.data.toBuffer()).toEqual(expected.data.toBuffer());
  expect(actual.clientIvcProof.toBuffer()).toEqual(expected.clientIvcProof.toBuffer());
  expect(actual.encryptedLogs.toBuffer()).toEqual(expected.encryptedLogs.toBuffer());
};

describe('Messages', () => {
  it('Correctly serializes and deserializes a single private transaction', () => {
    const transaction = mockTx();
    const message = transaction.toBuffer();
    const decodedTransaction = Tx.fromBuffer(message);
    verifyTx(decodedTransaction, transaction);
  });
});
