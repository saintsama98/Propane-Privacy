//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/*compliance registry | wallet-to-investor resolution and the attested record read by every rule head*/
/// @title IPropaneComplianceRegistry
/// @author Propane
/// @notice external surface of the registry / resolves a wallet to its investor and answers what is attested about them
abstract contract IPropaneComplianceRegistry {
    //compliance base pointers
    uint8 public constant KYC_APPROVED = 0;
    uint8 public constant REJECTED = 1;
    uint8 public constant PENDING = 2;

    uint8 public constant ACCREDITED = 3;

    //base modifiers

    function registerInvestor(string calldata _id, string calldata _collision_hash) public virtual returns (bool);

    function removeInvestor(string calldata _id) public virtual returns (bool);

    function setCountry(string calldata _id, string memory _country) public virtual returns (bool);

    function getCountry(string memory _id) public view virtual returns (string memory);

    function getInvestor(address _address) public view virtual returns (string memory);

    function isAccreditedInvestor(string calldata _id) external view virtual returns (bool);

    function isAccreditedInvestor(address _wallet) external view virtual returns (bool);

    //wallet level surface is ignored for now deliberately
}
