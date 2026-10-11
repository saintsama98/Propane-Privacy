//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

abstract contract PropaneInstitutionalStore {
    /// @custom:storage-location erc7201:propane.storage.Institutional
    struct InstitutionalStorage {
        mapping(uint256 serviceId => address service) services;
    }

    // erc7201("propane.storage.Institutional")
    bytes32 private constant INSTITUTIONAL_STORAGE = 0x1f794516286f040aa8f3db4670ced81192209afedd1d04c31f856911955be500;

    /// @dev `storage` here is an alias, not a copy.
    function _institutional() internal pure returns (InstitutionalStorage storage $) {
        bytes32 s = INSTITUTIONAL_STORAGE;
        assembly {
            $.slot := s
        }
    }
}
