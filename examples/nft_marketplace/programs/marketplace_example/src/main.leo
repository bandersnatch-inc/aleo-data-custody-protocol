import data_custody_protocol.aleo;
import arc721_example.aleo;
import credits.aleo;

program marketplace_example.aleo {
    const address_gen: group = 522678458525321116977504528531602186870683848189190546523208313015552693483group;
    inline viewkey_to_address(view_key: scalar) -> address {
         return (view_key * address_gen) as address;
    }

    const MPC_THRESHOLD: u8 = 8u8;

    struct ListingData {
        price: u64,
        seller: address,
        dcp_key: field
    }
    
    record NFTView{
        owner: address,
        data: data,
        edition: scalar
    }


    mapping listings: field => ListingData; 
    // nft_commit => listing_data;

    mapping listings_buyer: field => address;
    // nft_commit => buyer;

    mapping dcp_keys: field => bool;


    inline commit_nft(
        nft_data: data,
        nft_edition: scalar
    ) -> field {
        let data_hash: field = BHP256::hash_to_field(nft_data);
        let commitment: field = BHP256::commit_to_field(data_hash, nft_edition);
        return commitment;
    }


    async transition list(
        private nft: arc721_example.aleo/NFT, // private nft record to list
        public price: u64, // total price paid by seller
        public dcp_key: field, // random scalar
        private secret_random_viewkey: scalar,
        private privacy_random_coefficients: [field; 15],
        public validators: [address; 16],
        public obfuscator: scalar
    ) -> (NFTView, Future) {
        let (nft_view, transfer_future): (arc721_example.aleo/NFTView, Future) 
            = arc721_example.aleo/transfer_private_to_public(
                nft, self.address
            );
        let secret: field = secret_random_viewkey as field;
        let nft_data_address: address = viewkey_to_address(secret_random_viewkey);
        let out_nft_view: NFTView = NFTView {
            owner: nft_data_address,
            data: nft.data,
            edition: nft.edition
        };
        let nft_commit: field = commit_nft(nft.data, nft.edition);

        let custody_data_as_program_future: Future =
            data_custody_protocol.aleo/add_private(
                secret, // private data_view_key: scalar,
                dcp_key, // private custody_key: field,
                privacy_random_coefficients, // private coefficients: [field; 15],
                validators, // private validators: [address; 16],
                MPC_THRESHOLD, // private threshold: u8 <= 15
                obfuscator
            );

        let list_future: Future = finalize_list(
            nft_commit,
            price,
            self.caller,
            dcp_key,
            transfer_future,
            custody_data_as_program_future
        );
        return (
            out_nft_view, 
            list_future,
        );
    }
    async function finalize_list(
        nft_commit: field,
        price: u64,
        seller: address,
        dcp_key: field,
        transfer_future: Future,
        custody_data_as_program_future: Future
    ) {
        transfer_future.await();
        custody_data_as_program_future.await();

        let listing_data: ListingData = ListingData{
            price: price,
            seller: seller,
            dcp_key: dcp_key
        };
        listings.set(nft_commit, listing_data);

        // IMPORTANT
        assert(dcp_keys.contains(dcp_key).not());
        dcp_keys.set(dcp_key, true);
    }


    async transition accept_listing(
        public nft_commit: field,
        private listing_data: ListingData,
        public validators: [address; 16],
        public validator_fee: u64,
        private protocol_fee_record: credits.aleo/credits,
        public current_block_height: u32,
        public custody_trace: field
        /*
            Validators associated with the listing can be retrieved using: 
                protocol_validators.aleo/validator_sets.get(
                    data_custody_protocol.aleo/custodies.get(
                        hash_custody(
                            Custody {
                                origin: marketplace_example.aleo,
                                custody_key: listing_data.dcp_key,
                                threshold: MPC_THRESHOLD,
                            }
                        )
                    )
                )

             = dcp_core_protocol.aleo/custodies.get(custody_hash).custody_trace;
        */
    ) -> (credits.aleo/credits, Future) {
        let pay_marketplace_future: Future =
            credits.aleo/transfer_public_as_signer(
                listing_data.seller,
                listing_data.price
            );

        let (
            change,
            request_open_future
        ): (
            credits.aleo/credits,
            Future
        ) =
            data_custody_protocol.aleo/request_open(
                listing_data.dcp_key, // private data_address: address,
                self.signer, // private to: address,
                MPC_THRESHOLD, // private threshold: u8,
                custody_trace, // public custody_trace: field,
                validators, // public validators: [address; 16],
                validator_fee, // private validator_fee: u64,
                protocol_fee_record, // private protocol_fee_record: credits.aleo/credits,
                current_block_height
            );
        let accept_listing_future: Future = finalize_accept_listing(
            self.caller,
            nft_commit,
            listing_data,
            pay_marketplace_future,
            request_open_future,
        );
        return (change, accept_listing_future);
    }
    async function finalize_accept_listing(
        caller: address,
        nft_commit: field,
        listing_data: ListingData,
        pay_marketplace_future: Future,
        request_open_future: Future
    ) {
        let retrieved_listing_data: ListingData = listings.get(nft_commit);
        assert_eq(retrieved_listing_data, listing_data);
        assert(listings_buyer.contains(nft_commit).not());
        listings_buyer.set(nft_commit, caller);
        
        pay_marketplace_future.await();
        request_open_future.await();
    }


    // {nft_data, nft_edition} are retrieved by executing 'dcp_reconstruct_secret_offchain.aleo' offchain on shares sent to buyer by validators
    async transition withdraw_nft(
        nft_data: data,
        nft_edition: scalar,
        listing_data: ListingData
    ) -> (arc721_example.aleo/NFT, Future) {
        let nft_commit: field = commit_nft(nft_data, nft_edition);
        
        let (
            purshased_nft,
            transfer_nft_to_buyer_future
        ): (arc721_example.aleo/NFT, Future) = arc721_example.aleo/transfer_public_to_private(
            nft_data,
            nft_edition,
            self.signer,
        );

        let accept_listing_future: Future = finalize_withdraw_nft(
            self.caller,
            nft_commit,
            listing_data,
            transfer_nft_to_buyer_future,
        );
        return (
            purshased_nft,
            accept_listing_future
        );
    }
    async function finalize_withdraw_nft(
        caller: address,
        nft_commit: field,
        listing_data: ListingData,
        transfer_nft_to_buyer_future: Future,
    ) {
        let retrieved_listing_data: ListingData = listings.get(nft_commit);
        assert_eq(retrieved_listing_data, listing_data);
        assert_eq(listings_buyer.get(nft_commit), caller);
        listings_buyer.remove(nft_commit);
        listings.remove(nft_commit);
        transfer_nft_to_buyer_future.await();
    }
}
