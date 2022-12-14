
module nft_dao::DAO {
    use aptos_framework::account::{SignerCapability, create_signer_with_capability, create_authorized_signer};
    use std::string::String;
    use aptos_token::property_map::PropertyMap;
    use aptos_std::bucket_table::BucketTable;
    use aptos_token::token::{Self, TokenId};
    use aptos_std::table::Table;
    use std::string;
    use aptos_framework::resource_account;
    use std::signer;
    use std::error;
    use aptos_std::table;
    use std::vector;
    use aptos_token::property_map;
    use std::token_type::get_token_type;
    use aptos_framework::timestamp;
    use aptos_std::bucket_table;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;

    /// Only DAO adminstrators can initialize the DAO
    const EONLY_ADMIN_CAN_INITIALIZE_DAO: u64 = 1;

    /// Only maximal = 1 and maximal immutable token can be used for DAO
    const ENOT_NFT_TOKEN: u64 = 2;

    /// This NFT has already enrolled in DAO
    const ETOKEN_ALREADY_ENROLLED_IN_DAO: u64 = 3;

    /// This account doesn't have enough voting weights
    const EVOTING_WEIGHTS_NOT_ENOUGH: u64 = 4;

    /// This account doesn't own this DAO's voting token
    const ENOT_OWN_THE_VOTING_DAO_TOKEN: u64 = 5;

    /// This function is supported in proposal
    const ENOT_SUPPROTED_FUNCTION: u64 = 6;

    /// Can only propose a start time in future
    const EPROPOSAL_START_TIME_SHOULD_IN_FUTURE: u64 = 7;

    /// Cannot only use membership token of the DAO
    const ENOT_A_MEMBER_TOKEN: u64 = 8;

    /// String length exceeds limits
    const ESTRING_TOO_LONG: u64 = 9;

    /// Proposal ended
    const EPROPOSAL_ENDED: u64 = 10;

    /// Propsoal already resolved
    const EPROPOSAL_RESOLVED: u64 = 11;

    /// Denominator should be bigger than 0
    const EDEMONINATOR_CANNOT_BE_AERO: u64 = 12;

    /// Denominator should be bigger or equal to numerator
    const ENUMERATOR_BIGGER_THAN_DENOMINATOR: u64 = 13;

    /// NOT ENOUGH PEOPLE VOTED
    const ENOT_ENOUGH_TOKEN_VOTED: u64 = 14;

    /// TOKEN VOTED FOR PROPOSAL
    const ETOKEN_ALREADY_VOTED: u64 = 15;

    /// Constants
    const PROPOSAL_UNRESOLVED: u8 = 0;
    const PROPOSAL_RESOLVED_PASSED: u8 = 1;
    const PROPOSAL_RESOLVED_NOT_PASSED: u8 = 2;

    const DEFALT_VOTING_WEIGHT: u64 = 1;
    const TRANSFER_FUND_DST: String = string::utf8(b"dst");
    const TRANSFER_FUND_AMOUNT: String = string::utf8(b"amount");
    const MUTATE_COLLECTION_MAX_CREATOR: String = string::utf8(b"creator");
    const MUTATE_COLLECTION_MAX_CNAME: String = string::utf8(b"collection_name");
    const MUTATE_COLLECTION_MAX_NMAX: String = string::utf8(b"new_maximum");

    struct DAO has key {
        /// Name of the DAO
        name: String,
        /// The threshold that the proposal can resolve. For example, 50% means at least 50% of NFT holder should vote to resolve the proposal
        resolve_threshold: ResolveThreshold,
        /// The NFT Collection that is used to govern the DAO
        governance_token: GovernanceToken, // This is the governance token or NFT used for voting
        /// The address of the creator account this DAO owns. THis account is a resource account that this DAO is an adminstrator of the controlled account
        controlled_account: address, // This is the nft creator account that this DAO governs, this accout should offer it signer cap to DAO account
        /// The voting duration
        voting_duration: u64,
        /// Total number of eligible member NFTs
        total_supply: u64,
        /// Minimum weight for proposal
        min_proposal_weight: u64,
        /// Proposal counter
        cur_largest_proposal_id: u64,
    }

    struct DAOAdmin has key {
        /// The signer capability of the DAO resource account
        dao_signer_cap: SignerCapability,
        /// The account that can acquire signer of this DAO resource account
        admin_address: address, // this is the multi-sig account created in step 1
    }

    struct ResolveThreshold has store {
        numerator: u64,
        denominator: u64,
    }

    /// The collection should only contains NFTs, where all token name only has 1 maximal and immutable
    /// The total supply is fixed with the token names.
    struct GovernanceToken has store {
        /// The creator address of this NFT collection
        creator: address,
        /// The collection name
        collection: String,
        /// Eligible token_ids that can vote. Value of the table is the weights of the token
        member_tokens: Table<TokenId, u64>
    }

    /// All proposals
    struct Proposals has key {
        proposals: Table<u64, Proposal>,
    }

    struct Proposal {
        /// Name of the proposal, limiting to 64 chars
        name: String,
        /// Description of the proposal, limiting to 512 chars
        description: String,
        /// The name of function to be executed
        function_name: String,
        /// The function arguments to be exectued
        function_args: PropertyMap,
        /// The start time of the voting
        start_time_sec: u64,
        /// Proposal results, unresolved, passed, not passed
        resolution: u8,
    }

    struct ProposalVotingStatistics has key {
        active_proposals: Table<u64, VotingStatistics>,
    }

    struct VotingStatistics {
        /// Total yes votes
        total_yes: u64,
        /// Total no notes
        total_no: u64,
        /// Token voted yes
        yes_votes: BucketTable<TokenId, address>, // address is the original voter's address for keeping a record of who voted
        /// Token voted no
        no_votes: BucketTable<TokenId, address>,
    }

    /// Function executed automatically when publishing the module to store the signer cap and admin address
    fun init_module(resource_account: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @source_addr);
        move_to(resource_account, DAOAdmin {
            dao_signer_cap: resource_signer_cap,
            admin_address: @source_addr
        });
        move_to(resource_account, Proposals {
            proposals: table::new()
        });
        move_to(resource_account, ProposalVotingStatistics {
            active_proposals: table::new()
        });
    }

    public entry fun initialize_dao(
        admin: &signer,
        name: String,
        nft_creator_address: address,
        threshold_numerator: u64,
        threshold_denominator: u64,
        voting_duration: u64,
        creator: address,
        collection_name: String,
        min_proposal_weight: u64,
    ) acquires DAOAdmin {
        let dao_admin = borrow_global<DAOAdmin>(@nft_dao);
        assert!(dao_admin.admin_address == signer::address_of(admin), error::permission_denied(EONLY_ADMIN_CAN_INITIALIZE_DAO));

        assert!(string::length(&name) < 128, error::invalid_argument(ESTRING_TOO_LONG));
        assert!(threshold_denominator > 0, )
        let dao_signer = get_dao_signer();
        move_to(
            &dao_signer,
            DAO {
                name,
                resolve_threshold: ResolveThreshold { numerator: threshold_numerator, denominator: threshold_denominator},
                governance_token: GovernanceToken { creator, collection: collection_name, member_tokens: table::new() },
                controlled_account: nft_creator_address,
                voting_duration,
                total_supply: 0,
                min_proposal_weight,
                cur_largest_proposal_id: 0,
            },
        );
    }

    /// Anyone can enroll an NFT into the DAO
    public entry fun join_dao(token_names: vector<String>, property_versions: vector<u64>) acquires DAO {
        let dao = borrow_global_mut<DAO>(@nft_dao);
        let gtoken = dao.governance_token;
        let i = 0;
        while (i < vector::length(&token_names)) {
            let token_name = *vector::borrow(&token_names, i);
            let property_version = *vector::borrow(&property_versions, i);

            let token_id = token::create_token_id_raw(gtoken.creator, gtoken.collection, token_name, property_version);
            assert!(get_token_type(token_id) == 1 || get_token_type(token_id) == 0, error::permission_denied(ENOT_NFT_TOKEN));
            assert!(table::contains(&gtoken.member_tokens, token_id), error::already_exists(ETOKEN_ALREADY_ENROLLED_IN_DAO));
            table::add(&mut gtoken.member_tokens, token_id, DEFALT_VOTING_WEIGHT);
            i = i + 1;
        };
    }

    /// only a token holder can propose
    public entry fun create_proposal(
        account: &signer,
        name: String,
        description: String,
        function_name: String,
        arg_names: vector<String>, // name of the arguments of the function to be called
        arg_values: vector<vector<u8>>, // bcs serailized values of argument values
        arg_types:vector<String>, // types of arguments. currently, we only support string, u8, u64, u128, bool, address.
        start_time_sec: u64,
        token_names: vector<String>,
        property_versions: vector<u64>,
    )acquires DAO, Proposals {
        let dao = borrow_global_mut<DAO>(@nft_dao);
        assert!(string::length(&name) <= 64, error::invalid_argument(ESTRING_TOO_LONG));
        assert!(string::length(&description) <= 512, error::invalid_argument(ESTRING_TOO_LONG));

        // verify the account's token has enough weights to create proposal
        let weights = get_voting_weights(account, &token_names, &property_versions, dao);
        assert!(weights >= dao.min_proposal_weight, error::permission_denied(EVOTING_WEIGHTS_NOT_ENOUGH));

        // verify the parameters are legit
        let pm = property_map::new(arg_names, arg_values, arg_types);
        assert_function_valid(function_name, &pm);

        // verify the start_time is in future
        let now = timestamp::now_seconds();
        assert!(start_time_sec > now, error::invalid_argument(EPROPOSAL_START_TIME_SHOULD_IN_FUTURE));

        let proposal = Proposal {
            name,
            description,
            function_name,
            function_args: pm,
            start_time_sec,
            resolution: PROPOSAL_UNRESOLVED,
        };

        let proposal_store = borrow_global_mut<Proposals>(@nft_dao);
        let proposal_id = dao.cur_largest_proposal_id + 1;
        table::add(&mut proposal_store.proposals, proposal_id, proposal);
        dao.cur_largest_proposal_id = proposal_id;
    }

    /// Vote with a batch of tokens
    public entry fun vote(
        account: &signer,
        proposal_id: u64,
        vote: bool,
        token_names: vector<String>,
        property_versions: vector<u64>,
    ) acquires DAO, ProposalVotingStatistics, Proposals {
        let dao = borrow_global_mut<DAO>(@nft_dao);
        let gtoken = dao.governance_token;
        let proposals = borrow_global<Proposals>(@nft_dao);

        /// assert the proposal hasn't ended
        let proposal = table::borrow(&proposals.proposals, proposal_id);
        let now = timestamp::now_seconds();
        assert!(now > proposal.start_time_sec + dao.voting_duration, error::invalid_argument(EPROPOSAL_ENDED));

        let prop_stats = borrow_global_mut<ProposalVotingStatistics>(@nft_dao);
        if (!table::contains(&prop_stats.active_proposals, proposal_id)) {
            let vstat = VotingStatistics {
                total_yes: 0,
                total_no: 0,
                yes_votes: bucket_table::new(10),
                no_votes: bucket_table::new(10),
            };
            table::add(&mut prop_stats.active_proposals, proposal_id, vstat);
        };
        let stats = table::borrow_mut(&mut prop_stats.active_proposals, proposal_id);

        let voter_addr = signer::address_of(account);
        let i = 0;
        while (i < vector::length(&token_names)) {
            let token_name = *vector::borrow(&token_names, i);
            let property_version = *vector::borrow(&property_versions, i);
            let token_id = token::create_token_id_raw(gtoken.creator, gtoken.collection, token_name, property_version);
            // check if this token already voted
            assert!(!bucket_table::contains(&stats.no_votes, &token_id), error::invalid_argument(ETOKEN_ALREADY_VOTED));
            assert!(!bucket_table::contains(&stats.yes_votes, &token_id), error::invalid_argument(ETOKEN_ALREADY_VOTED));

            // this account owns the token
            assert!(token::balance_of(signer::address_of(account), token_id) == 1, error::permission_denied(ENOT_OWN_THE_VOTING_DAO_TOKEN));
            // this token is a member token
            assert!(table::contains(&gtoken.member_tokens, token_id), error::permission_denied(ENOT_A_MEMBER_TOKEN));
            if (vote) {
                stats.total_yes = stats.total_yes + *table::borrow(&gtoken.member_tokens, token_id);
                bucket_table::add(&mut stats.yes_votes, token_id, voter_addr);
            } else {
                stats.total_no = stats.total_no + *table::borrow(&gtoken.member_tokens, token_id);
                bucket_table::add(&mut stats.no_votes, token_id, voter_addr);
            };
            i = i + 1;
        };
    }

    /// Entry function that can be called by anyone
    public entry fun resolve(proposal_id: u64) acquires Proposals, DAO, ProposalVotingStatistics, DAOAdmin {
        // validate if proposal is ready to resolve
        let dao = borrow_global_mut<DAO>(@nft_dao);

        /// assert the proposal voting ended
        let proposals = borrow_global_mut<Proposals>(@nft_dao);
        let proposal = table::borrow_mut(&mut proposals.proposals, proposal_id);
        let now = timestamp::now_seconds();
        assert!(now < proposal.start_time_sec + dao.voting_duration, error::invalid_argument(EPROPOSAL_ENDED));

        // assert the proposal is unresolved yet
        assert!(proposal.resolution == PROPOSAL_UNRESOLVED, error::invalid_argument(EPROPOSAL_RESOLVED));

        let active_proposal = borrow_global_mut<ProposalVotingStatistics>(@nft_dao).active_proposals;
        let voting_stat = table::remove(&mut active_proposal, proposal_id);
        // validate resolve threshold and result
        let voted = voting_stat.total_no + voting_stat.total_yes;
        if (voted * dao.resolve_threshold.denominator <= dao.resolve_threshold.numerator * dao.total_supply) {
            // not sufficient token voted
            proposal.resolution = PROPOSAL_RESOLVED_NOT_PASSED;
            return;
        };

        let passed = if (voting_stat.total_yes > voting_stat.total_no) {true} else {false};
        if (passed) {
            let function_name = proposal.function_name;
            if (function_name == string::utf8(b"transfer_fund")){
                let dst_addr = property_map::read_address(&proposal.function_args, &TRANSFER_FUND_DST);
                let amount = property_map::read_u64(&proposal.function_args, &TRANSFER_FUND_AMOUNT);
                transfer_fund(dst_addr, amount);
            } else if (function_name == string::utf8(b"mutate_collection_maximum")) {
                let creator = property_map::read_address(&proposal.function_args, &MUTATE_COLLECTION_MAX_CREATOR);
                let cname = property_map::read_string(&proposal.function_args, &MUTATE_COLLECTION_MAX_CNAME);
                let nmax = property_map::read_u64(&proposal.function_args, &MUTATE_COLLECTION_MAX_NMAX);
                mutate_collection_maximum(creator, cname, nmax);
            } else {
               assert!(function_name == string::utf8(b"no_op"), error::invalid_argument(ENOT_SUPPROTED_FUNCTION));
            };
            proposal.resolution = PROPOSAL_RESOLVED_PASSED;
        } else {
            proposal.resolution = PROPOSAL_RESOLVED_NOT_PASSED;
        };
    }

    // transfer APT fund from the DAO account to the destination account
    fun transfer_fund(dst: address, amount: u64) acquires DAOAdmin {
        coin::transfer<AptosCoin>(&get_dao_signer(), dst, amount);
    }

    // change maximum of collection. This is only supported for NFT collection having signer delegation
    fun mutate_collection_maximum(creator: address, collection_name: String, new_maximum: u64)acquires DAOAdmin {
        let dao_signer = get_dao_signer();
        let creator_signer = create_authorized_signer(&dao_signer, creator);
        token::mutate_collection_maximum(&creator_signer, collection_name, new_maximum);
    }

    fun get_voting_weights(
        account: &signer,
        token_names: &vector<String>,
        property_versions: &vector<u64>,
        dao: &DAO
    ): u64 {
        let gtoken = dao.governance_token;
        let i = 0;
        let total_weight = 0;
        while (i < vector::length(token_names)) {
            let token_name = *vector::borrow(token_names, i);
            let property_version = *vector::borrow(property_versions, i);
            let token_id = token::create_token_id_raw(gtoken.creator, gtoken.collection, token_name, property_version);
            assert!(token::balance_of(signer::address_of(account), token_id) == 1, error::permission_denied(ENOT_OWN_THE_VOTING_DAO_TOKEN));
            assert!(table::contains(&gtoken.member_tokens, token_id), error::permission_denied(ENOT_A_MEMBER_TOKEN));

            total_weight = total_weight + *table::borrow(&gtoken.member_tokens, token_id);
            i = i + 1;
        };
        total_weight
    }

    fun assert_function_valid(function_name: String, map: &PropertyMap){
        if (function_name == string::utf8(b"transfer_fund")) {
            assert!(property_map::length(map) == 2, error::invalid_argument(ENOT_SUPPROTED_FUNCTION));
            property_map::read_address(map, &TRANSFER_FUND_DST);
            property_map::read_u64(map, &TRANSFER_FUND_AMOUNT);
        } else if (function_name == string::utf8(b"no_op")) {
            assert!(property_map::length(map) == 0, error::invalid_argument(ENOT_SUPPROTED_FUNCTION));
        } else if (function_name == string::utf8(b"mutate_collection_maximum")) {
            assert!(property_map::length(map) == 2, error::invalid_argument(ENOT_SUPPROTED_FUNCTION));
            property_map::read_string(map, &MUTATE_COLLECTION_MAX_CNAME);
            property_map::read_u64(map, &MUTATE_COLLECTION_MAX_NMAX);
        } else {
            abort error::invalid_argument(ENOT_SUPPROTED_FUNCTION)
        }
    }

    fun get_dao_signer(): signer acquires DAOAdmin {
        let dao_admin = borrow_global<DAOAdmin>(@nft_dao);
        create_signer_with_capability(&dao_admin.dao_signer_cap)
    }

}
