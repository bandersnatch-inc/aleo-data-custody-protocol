
/*
    Reconstruct a secret from shares.

    Usage:
    - Reconstruct 3 shares:
        leo run reconstruct_secret_offchain "[
            {share_val:3142197879141985field,index:1field}, \
            {share_val:28673026215703456field,index:4field}, \
            {share_val:42551380561059241field,index:5field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field}, \
            {share_val:0field,index:0field} \
        ]"

    contact@aleo.store - Pierre-André LONG
*/


program dcp_reconstruct_secret_offchain.aleo {
    const MAX_SHARES: u8 = 16u8;

    struct Share {
        share_val: field,
        index: field
    }

    // Inverse field but will invert 0field to 1field to avoid constraint error
    inline safe_inv(f: field) -> field { 
        return ((f == 0field) ? 1field : f).inv();
    }


    function reconstruct_offchain(shares: [Share; 16]) -> field { // MAX_SHARES
        let secret: field = 0field;
        for i: u8 in 0u8..MAX_SHARES{
            let lagrange_coeff: field = 1field;
            let x_i: field = shares[i].index;
            for j: u8 in 0u8..MAX_SHARES {
                let x_j: field = shares[j].index;
                let to_mul: field = 
                    (i != j && x_j != 0field) ? 
                        (x_j * safe_inv(x_j - x_i)) :
                        1field;
                lagrange_coeff *= to_mul;
            }
            secret += (x_i != 0field) ?
                    ((shares[i].share_val) * lagrange_coeff) :
                    0field;
        }
        return secret;
    }

    transition reconstruct_secret_offchain(
        shares: [Share; 16]  // MAX_SHARES
    ) -> field {
        let reconstructed_secret: field = reconstruct_offchain(shares);
        return reconstructed_secret;
    }
}
