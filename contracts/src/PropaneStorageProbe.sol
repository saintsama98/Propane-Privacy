// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @notice Bucket 0 wiring probe: proves the toolchain, remappings and the
///         ERC-7201 storage convention all resolve. Not part of the system.
/// @custom:storage-location erc7201:propane.storage.Probe
contract PropaneStorageProbe is Initializable, UUPSUpgradeable {
    struct ProbeStorage {
        uint256 value;
    }

    // erc7201("propane.storage.Probe")
    bytes32 private constant PROBE_STORAGE =
        keccak256(abi.encode(uint256(keccak256("propane.storage.Probe")) - 1)) & ~bytes32(uint256(0xff));

    function _probe() private pure returns (ProbeStorage storage $) {
        bytes32 s = PROBE_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(uint256 v) external initializer {
        _probe().value = v;
    }

    function value() external view returns (uint256) {
        return _probe().value;
    }

    function slot() external pure returns (bytes32) {
        return PROBE_STORAGE;
    }

    function _authorizeUpgrade(address) internal virtual override {}
}
