/// A resource account is used to manage resources independent of an account managed by a user.
/// This contains several utilities to make using resource accounts more effective.
///
/// A dev wishing to use resource accounts for a liquidity pool, would likely do the following:
/// 1. Create a new account using `Resourceaccount::create_resource_account`. This creates the
/// account, move the creator's account address to the resource account delegator and rotates the key to
/// the current accounts authentication key or a provided authentication key.
/// 2. Define the LiquidityPool module's address to be the same as the resource account.
/// 3. Construct a ModuleBundle payload for the resource account using the authentication key used
/// in step 1.
/// 4. In the LiquidityPool module's `init_module` function, call `retrieve_resource_account_cap`
/// which will retrive the `signer_cap` and rotate the resource account's authentication key to
/// `0x0`, effectively locking it off.
/// 5. When adding a new coin, the liquidity pool will load the capability and hence the signer to
/// register and store new LiquidityCoin resources.
///
/// Code snippets to help:
/// ```
/// fun init_module(source: &signer) {
///   let dev_address = @DEV_ADDR;
///   let signer = account::acquire_signer(source, dev_address);
///   let lp = LiquidityPoolInfo {, ... };
///   move_to(&signer, lp);
/// }
/// ```
///
/// Later on during a coin registration:
/// ```
/// public fun add_coin<X, Y>(lp: &LP, x: Coin<x>, y: Coin<y>) {
///     if(!exists<LiquidityCoin<X, Y>(LP::Address(lp), LiquidityCoin<X, Y>)) {
///         let mint, burn = Coin::initialize<LiquidityCoin<X, Y>>(...);
///         move_to(&code_signer(), LiquidityCoin<X, Y>{ mint, burn });
///     }
///     ...
/// }
/// ```
module aptos_framework::resource_account {
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_std::simple_map::{Self, SimpleMap};

    /// Container resource not found in account
    const ECONTAINER_NOT_PUBLISHED: u64 = 1;

    struct Container has key {
        store: SimpleMap<address, account::SignerCapability>,
    }

    struct ResourceAccounts has key {
        accounts: vector<address>,
    }

    /// Creates a new resource account and rotates the authentication key to either
    /// the optional auth key if it is non-empty (though auth keys are 32-bytes)
    /// or the source accounts current auth key.
    public entry fun create_resource_account(
        origin: &signer,
        seed: vector<u8>,
        optional_auth_key: vector<u8>,
    ) acquires Container, ResourceAccounts {
        let resource_signer = account::create_resource_account_v2(origin, seed, false);

        let origin_addr = signer::address_of(origin);
        if (!exists<Container>(origin_addr)) {
            move_to(origin, Container { store: simple_map::create() })
        };

        // add resource account address to the container
        let addr = signer::address_of(&resource_signer);
        if (exists<ResourceAccounts>(origin_addr)) {
            let store = borrow_global_mut<ResourceAccounts>(origin_addr);
            if (!vector::contains(&store.accounts, &addr)) {
                vector::push_back(&mut store.accounts, addr)
            }
        }
        else {
            // skip
        };
        account::delegate_signer(&resource_signer, origin_addr);


        let auth_key = if (vector::is_empty(&optional_auth_key)) {
            account::get_authentication_key(origin_addr)
        } else {
            optional_auth_key
        };
        account::rotate_authentication_key_internal(&resource_signer, auth_key);
    }

    /// When called by the resource account, it will retrieve the capability associated with that
    /// account and rotate the account's auth key to 0x0 making the account inaccessible without
    /// the SignerCapability.
    public fun retrieve_resource_account_cap(
        resource: &signer,
        source_addr: address,
    ): account::SignerCapability acquires Container {
        abort(1);
        assert!(exists<Container>(source_addr), error::not_found(ECONTAINER_NOT_PUBLISHED));

        let resource_addr = signer::address_of(resource);
        let (resource_signer_cap, empty_container) = {
            let container = borrow_global_mut<Container>(source_addr);
            let (_resource_addr, signer_cap) = simple_map::remove(&mut container.store, &resource_addr);
            (signer_cap, simple_map::length(&container.store) == 0)
        };

        if (empty_container) {
            let container = move_from(source_addr);
            let Container { store } = container;
            simple_map::destroy_empty(store);
        };

        let zero_auth_key = x"0000000000000000000000000000000000000000000000000000000000000000";
        let resource = account::create_signer_with_capability(&resource_signer_cap);
        account::rotate_authentication_key_internal(&resource, zero_auth_key);
        resource_signer_cap
    }

    public fun retrieve_resource_account_signer(): signer {
        resource:
    }

    #[test(user = @0x1111)]
    public entry fun end_to_end(user: signer) acquires Container {
        use std::bcs;
        use std::hash;

        let user_addr = signer::address_of(&user);
        account::create_account(user_addr);

        let seed = x"01";
        let bytes = bcs::to_bytes(&user_addr);
        vector::append(&mut bytes, copy seed);
        let resource_addr = aptos_std::from_bcs::to_address(hash::sha3_256(bytes));

        create_resource_account(&user, seed, vector::empty());
        let container = borrow_global<Container>(user_addr);
        let resource_cap = simple_map::borrow(&container.store, &resource_addr);

        let resource = account::create_signer_with_capability(resource_cap);
        let _resource_cap = retrieve_resource_account_cap(&resource, user_addr);
    }
}
