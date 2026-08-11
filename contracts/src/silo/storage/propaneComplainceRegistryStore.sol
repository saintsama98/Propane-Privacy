//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/*compliance registry storage | the investor record, the wallet map and the attested attributes*/
/// @title PropaneComplainceRegistryStore
/// @author Propane
/// @notice storage layer for the compliance registry / shape is fixed by the confidentiality decision, not yet recorded
contract PropaneComplainceRegistryStore {
    //storage

    struct Investor {
        string id;
        string collisionHash;
        string country;
    }
    mapping(string investorId => Investor investor) internal investors;
}
