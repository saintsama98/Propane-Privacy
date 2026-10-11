//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {PropaneAttributes} from "../../interfaces/IPropaneServices.sol";

/*compliance registry storage | registration flag and the encrypted attested attributes*/
/// @title PropaneComplianceRegistryStore
/// @author Propane
/// @notice Storage layer for the compliance registry. One wallet is one investor: an investor
///         holding several wallets is counted once per wallet, which is a known limitation.
abstract contract PropaneComplianceRegistryStore {
    struct WalletRecord {
        bool registered;
        PropaneAttributes attrs;
    }

    /// @custom:storage-location erc7201:propane.storage.ComplianceRegistry
    struct ComplianceRegistryStorage {
        mapping(address wallet => WalletRecord record) records;
        /// @dev Every wallet ever registered, in order. Registration is public, so this list
        ///      discloses nothing new; it lets the census be recomputed from chain state.
        address[] wallets;
    }

    // erc7201("propane.storage.ComplianceRegistry")
    bytes32 private constant COMPLIANCE_REGISTRY_STORAGE =
        0x02f49ddf4b744a75c5f79c27202f12e5aec701d5f269e4808995365ed6358000;

    /// @dev `storage` here is an alias, not a copy.
    function _complianceRegistry() internal pure returns (ComplianceRegistryStorage storage $) {
        bytes32 s = COMPLIANCE_REGISTRY_STORAGE;
        assembly {
            $.slot := s
        }
    }
}
