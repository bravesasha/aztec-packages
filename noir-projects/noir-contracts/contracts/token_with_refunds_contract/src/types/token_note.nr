use dep::aztec::{
    generators::{Ga1 as G_amt, Ga2 as G_npk, Ga3 as G_rnd},
    prelude::{NoteHeader, NoteInterface, PrivateContext},
    protocol_types::{
    constants::GENERATOR_INDEX__NOTE_NULLIFIER, point::Point, scalar::Scalar,
    hash::poseidon2_hash_with_separator
},
    note::utils::compute_note_hash_for_consumption, oracle::unsafe_rand::unsafe_rand,
    keys::getters::get_nsk_app, note::note_getter_options::PropertySelector
};
use dep::std::{embedded_curve_ops::multi_scalar_mul, hash::from_field_unsafe};

trait OwnedNote {
    fn new(amount: U128, owner_npk_m_hash: Field) -> Self;
    fn get_amount(self) -> U128;
    fn get_owner_npk_m_hash(self) -> Field;
    fn get_owner_selector() -> PropertySelector;
}

trait PrivatelyRefundable {
    fn generate_refund_points(
        fee_payer_npk_m_hash: Field,
        user_npk_m_hash: Field,
        user_randomness: Field,
        fee_payer_randomness: Field
    ) -> (Point, Point);

    fn complete_refund(
        incomplete_fee_payer_point: Point,
        incomplete_user_point: Point,
        funded_amount: Field,
        transaction_fee: Field
    ) -> (Field, Field);
}

global TOKEN_NOTE_LEN: Field = 3; // 3 plus a header.
global TOKEN_NOTE_BYTES_LEN: Field = 3 * 32 + 64;

#[aztec(note)]
struct TokenNote {
    // The amount of tokens in the note
    amount: U128,
    // The nullifying public key hash is used with the nsk_app to ensure that the note can be privately spent.
    npk_m_hash: Field,
    // Randomness of the note to hide its contents
    randomness: Field,
}

impl NoteInterface<TOKEN_NOTE_LEN, TOKEN_NOTE_BYTES_LEN> for TokenNote {
    // docs:start:nullifier
    fn compute_note_hash_and_nullifier(self, context: &mut PrivateContext) -> ( Field, Field ) {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = context.request_nsk_app(self.npk_m_hash);
        let nullifier = poseidon2_hash_with_separator([note_hash_for_nullify, secret], GENERATOR_INDEX__NOTE_NULLIFIER);
        (note_hash_for_nullify, nullifier)
    }
    // docs:end:nullifier

    fn compute_note_hash_and_nullifier_without_context(self) -> ( Field, Field ) {
        let note_hash_for_nullify = compute_note_hash_for_consumption(self);
        let secret = get_nsk_app(self.npk_m_hash);
        let nullifier = poseidon2_hash_with_separator([note_hash_for_nullify,secret,],GENERATOR_INDEX__NOTE_NULLIFIER);
        (note_hash_for_nullify, nullifier)
    }

    fn compute_note_hiding_point(self) -> Point {
        // We use the unsafe version because the multi_scalar_mul will constrain the scalars.
        let npk_m_hash_scalar = from_field_unsafe(self.npk_m_hash);
        let randomness_scalar = from_field_unsafe(self.randomness);
        // We compute the note hiding point as `G_amt * amount + G_npk * npk_m_hash + G_rnd * randomness` instead
        // of using pedersen or poseidon2 because it allows us to privately add and subtract from amount in public
        // by leveraging homomorphism.
        multi_scalar_mul(
            [G_amt, G_npk, G_rnd],
            [Scalar {
                lo: self.amount.to_integer(),
                hi: 0
            },
            npk_m_hash_scalar,
            randomness_scalar]
        )
    }
}

impl Eq for TokenNote {
    fn eq(self, other: Self) -> bool {
        (self.amount == other.amount) &
        (self.npk_m_hash == other.npk_m_hash) &
        (self.randomness == other.randomness)
    }
}

impl OwnedNote for TokenNote {
    fn new(amount: U128, owner_npk_m_hash: Field) -> Self {
        Self {
            amount,
            npk_m_hash: owner_npk_m_hash,
            randomness: unsafe_rand(),
            header: NoteHeader::empty(),
        }
    }

    fn get_amount(self) -> U128 {
        self.amount
    }

    fn get_owner_npk_m_hash(self) -> Field {
        self.npk_m_hash
    }

    fn get_owner_selector() -> PropertySelector {
        PropertySelector { index: 1, offset: 0, length: 32 }
    }
}

/**
 * What is happening below?
 *
 * First in generate_refund_points, we create two points on the grumpkin curve;
 * these are going to be eventually turned into notes:
 * one for the user, and one for the fee payer.
 *
 * So you can think of these (x, y) points as "partial notes": they encode part of the internals of the notes.
 *
 * This is because the compute_note_hiding_point function above defines the hiding point as:
 *
 * G_amt * amount + G_npk * npk_m_hash + G_rnd * randomness
 * 
 * where G_amt, G_npk and G_rnd are generator points. Interesting point here is that we actually need to convert
 * - amount
 * - npk_m_hash
 * - randomness
 * from grumpkin Field elements
 * (which have a modulus of 21888242871839275222246405745257275088548364400416034343698204186575808495617)
 * into a grumpkin scalar
 * (which have a modulus of 21888242871839275222246405745257275088696311157297823662689037894645226208583)
 *
 * The intuition for this is that the Field elements define the domain of the x, y coordinates for points on
 * the curves, but the number of points on the curve is actually greater than the size of that domain.
 *
 * (Consider, e.g. if the curve were defined over a field of 10 elements, and each x coord had two corresponding
 * y for +/-)
 *
 * For a bit more info, see
 * https://hackmd.io/@aztec-network/ByzgNxBfd#2-Grumpkin---A-curve-on-top-of-BN-254-for-SNARK-efficient-group-operations
 *
 *
 * Anyway, if we have a secret scalar s, and then we reveal a point s * G (G being a generator), there is no efficient
 * way to deduce what s is. This is the discrete log problem.
 *
 * However we can still perform addition/subtraction on points! That is why we generate those two points, which are:
 * incomplete_fee_payer_point := G_npk * fee_payer_npk + G_rnd * fee_payer_randomness
 * incomplete_user_point := G_npk * user_npk + G_rnd * user_randomness
 *
 * So we pass those points into the teardown function (here) and compute a third point corresponding to the transaction
 * fee as just:
 *
 * fee_point := G_amt * transaction_fee
 * refund_point := G_amt * (funded_amount - transaction_fee)
 *
 * where `funded_amount` is the total amount in tokens that the sponsored user initially supplied and the transaction
 * fee is the final transaction fee whose value is made available in the public teardown function.
 *
 * Then we arrive at the final points via addition of the fee and refund points:
 *
 * fee_payer_point := incomplete_fee_payer_point + fee_point =
 *                  = (G_npk * fee_payer_npk + G_rnd * fee_payer_randomness) + G_amt * transaction_fee =
 *                  = G_amt * transaction_fee + G_npk * fee_payer_npk + G_rnd * fee_payer_randomness
 *
 * user_point := incomplete_user_point + refund_point =
 *             = (G_npk * user_npk + G_rnd + user_randomness) + G_amt * (funded_amount - transaction_fee) =
 *             = G_amt * (funded_amount - transaction_fee) + G_npk * user_npk + G_rnd * user_randomness
 * 
 * The point above matches the note_hiding_point of (and therefore *is*) notes like:
 * {
 *     amount: (funded_amount - transaction_fee),
 *     npk_m_hash: user_npk,
 *     randomness: user_randomness
 * }
 *
 * Why do we need different randomness for the user and the fee payer notes?
 * --> This is because if the randomness values were the same we could fingerprint the user by doing the following:
 *      1) randomness_influence = incomplete_fee_payer_point - G_npk * fee_payer_npk =
 *                              = (G_npk * fee_payer_npk + G_rnd * randomness) - G_npk * fee_payer_npk =
 *                              = G_rnd * randomness
 *      2) user_fingerprint = incomplete_user_point - randomness_influence =
 *                          = (G_npk * user_npk + G_rnd * randomness) - G_rnd * randomness =
 *                          = G_npk * user_npk
 *      3) Then the second time the user would use this fee paying contract we would recover the same fingerprint and
 *         link that the 2 transactions were made by the same user. Given that it's expected that only a limited set
 *         of fee paying contracts will be used and they will be known, searching for fingerprints by trying different
 *         fee payer npk values of these known contracts is a feasible attack.
 */
impl PrivatelyRefundable for TokenNote {
    fn generate_refund_points(fee_payer_npk_m_hash: Field, user_npk_m_hash: Field, user_randomness: Field, fee_payer_randomness: Field) -> (Point, Point) {
        // 1. To be able to multiply generators with randomness and npk_m_hash using barretneberg's (BB) blackbox
        // function we first need to convert the fields to high and low limbs.
        // We use the unsafe version because the multi_scalar_mul will constrain the scalars.
        let fee_payer_randomness_scalar = from_field_unsafe(fee_payer_randomness);
        let fee_payer_npk_m_hash_scalar = from_field_unsafe(fee_payer_npk_m_hash);

        // 2. Now that we have correct representationsn of fee payer and randomness we can compute
        // `G_npk * fee_payer_npk + G_rnd * randomness`.
        let incomplete_fee_payer_point = multi_scalar_mul(
            [G_npk, G_rnd],
            [fee_payer_npk_m_hash_scalar, fee_payer_randomness_scalar]
        );

        // 3. We do the necessary conversion for values relevant for the sponsored user point.
        // We use the unsafe version because the multi_scalar_mul will constrain the scalars.
        let user_npk_m_hash_scalar = from_field_unsafe(user_npk_m_hash);
        let user_randomness_scalar = from_field_unsafe(user_randomness);

        // 4. We compute `G_npk * user_npk_m_hash + G_rnd * randomness`.
        let incomplete_user_point = multi_scalar_mul(
            [G_npk, G_rnd],
            [user_npk_m_hash_scalar, user_randomness_scalar]
        );

        // 5. At last we return the points.
        (incomplete_fee_payer_point, incomplete_user_point)
    }

    fn complete_refund(incomplete_fee_payer_point: Point, incomplete_user_point: Point, funded_amount: Field, transaction_fee: Field) -> (Field, Field) {
        // 1. We check that user funded the fee payer contract with at least the transaction fee.
        assert(!funded_amount.lt(transaction_fee), "tx fee is higher than funded amount"); // funded_amout >= transaction_fee

        // 2. We convert the transaction fee and refund amount to high and low limbs to be able to use BB API.
        // We use the unsafe version because the multi_scalar_mul will constrain the scalars.
        let transaction_fee_scalar = from_field_unsafe(transaction_fee);
        let refund_scalar = from_field_unsafe(funded_amount - transaction_fee);

        // 3. We compute the fee point as `G_amt * transaction_fee`
        let fee_point = multi_scalar_mul([G_amt], [transaction_fee_scalar]);

        // 4. We compute the refund point as `G_amt * refund`
        let refund_point = multi_scalar_mul([G_amt], [refund_scalar]);

        // 5. Now we leverage homomorphism to privately add the fee to fee payer point and we add refund to the user point.
        let fee_payer_point = incomplete_fee_payer_point + fee_point;
        let user_point = incomplete_user_point + refund_point;

        // 6. We no longer need to do any elliptic curve operations with the points so we collapse them to the final
        // note hashes.
        let fee_payer_note_hash = fee_payer_point.x;
        let user_note_hash = user_point.x;

        // 7. Finally we return the hashes.
        (fee_payer_note_hash, user_note_hash)
    }
}
