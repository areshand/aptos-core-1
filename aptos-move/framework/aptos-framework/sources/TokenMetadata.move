module AptosFramework::CustomTokendata {
    use AptosFramework::Table::{Self, Table};
    use Std::ASCII;
    use Std::Option::Option;


    struct CustomTokendata has store {
        // can owner update the properties
        is_mutable: bool,
        // store key, value pairs defined for each token edition
        properties: Table<vector<u8>, vector<u8>>,

    }
}
