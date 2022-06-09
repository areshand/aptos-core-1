module AptosFramework::Token2 {
    use Std::ASCII;
    use Std::Errors;
    use Std::Event::{Self, EventHandle};
    use Std::Option::{Self, Option};
    use Std::Signer;
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::CustomTokendata::CustomTokendata;
    use AptosFramework::TypeInfo;
    use AptosFramework::BigVector::BigVector;

    /// Represents ownership of a the data associated with this Token
    /// T can be used represent sward, arrow, etc different types.
    struct Token<T> has store {
        // global unique identifier of this token
        id: TokenId,
        // whether this token is updatable, only master edition updatable could be true
        is_mutable: bool,
        // Describes this Token
        description: ASCII::String,
        // Optional maximum number of this type of Token.
        maximum: Option<u64>,
        // Total number of this type of Token
        supply: Option<u64>,
        // URL for additional information / media
        uri: ASCII::String,
        //custom properties
        metadata: CustomTokendata,
    }

    /// Represents a unique identity for the token
    struct TokenId has copy, drop, store {
        // The creator of this token
        creator: address,
        // The collection or set of related tokens within the creator's account
        collection: ASCII::String,
        // Unique name within a collection within the creator's account
        name: ASCII::String,
        // the edition of the token. 0 is the master edition
        edition: u64,
        // type information
        type_info: Option<TypeInfo::TypeInfo>
    }

    /// Represents token resources owned by token owner
    struct TokenStore has key {
        tokens: BigVector<TokenId>,
    }

    public(script) fun print<T>(master_owner: &signer, quantity: u64): Token<T> {

    }
}
