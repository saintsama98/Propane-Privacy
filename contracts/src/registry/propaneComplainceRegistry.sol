//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IPropaneComplianceRegistry} from "./IPropaneComplianceRegistry.sol";
import {PropaneComplainceRegistryStore} from "../silo/storage/propaneComplainceRegistryStore.sol";

/*compliance registry | wallet-to-investor resolution and the attested record read by every rule head*/
/// @title PropaneComplainceRegistry
/// @author Propane
/// @notice resolves a wallet to its investor and holds what is attested about them / consulted on every transfer
abstract contract PropaneComplainceRegistry is IPropaneComplianceRegistry, PropaneComplainceRegistryStore {
    function registerInvestor(string calldata _id, string calldata collisionHash) public override returns (bool) {
        investors[_id] = Investor(_id, collisionHash, "");
        return true;
    }

    function removeInvestor(string calldata _id) public override returns (bool) {
        /*base checks are not implement ready yet*/
        delete investors[_id];
        return true;
    }

    function setCountry(string calldata _id, string memory _country) public override returns (bool) {
        /*country is unvalidated free text for now; the reference lets a typo fall through to an
          unmapped region and bypass the restriction, so this needs a validated type before use*/
        investors[_id].country = _country;
        return true;
    }

    function getCountry(string memory _id) public view override returns (string memory) {
        return investors[_id].country;
    }
}
