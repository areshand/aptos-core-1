module AptosFramework::Collection {
    use Std::ASCII;
    use Std::Errors;
    use Std::Event::{Self, EventHandle};
    use Std::Option::{Self, Option};
    use Std::Signer;
    use AptosFramework::Table::{Self, Table};
    use AptosFramework::Token2::{TokenId, Token};
    use AptosFramework::BigVector::BigVector;
    use AptosFramework::TypeInfo;

    /// Represent all the creat
    struct Collections has key {
        collections: BigVector<CollectionId>,
    }

    struct CollectionId {
        // The creator of this token
        creator: address,
        // The collection or set of related tokens within the creator's account
        collection: ASCII::String,
        // type information
        type_info: Option<TypeInfo::TypeInfo>
    }

    /// Represent the collection metadata
    struct Collection<T> has store {
        // Describes the collection
        description: ASCII::String,
        // Unique name within this creators account for this collection
        name: ASCII::String,
        // URL for additional information /media
        uri: ASCII::String,
        // Total number of distinct Tokens tracked by the collection
        count: u64,
        // Optional maximum number of tokens allowed within this collections
        maximum: Option<u64>,
        // the master editions belong to this collection
        tokens: Table<TokenId, Token<T>>,
    }
}
