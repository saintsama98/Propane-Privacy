// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PropaneComplianceRegistryStorage} from "../../src/storage/PropaneComplianceRegistryStorage.sol";
import {PropaneInstitutionalStorage} from "../../src/storage/PropaneInstitutionalStorage.sol";

contract RegistryStoreHarness is PropaneComplianceRegistryStorage {
    function register(address wallet) external {
        _complianceRegistry().records[wallet].registered = true;
    }
}

contract InstitutionalStoreHarness is PropaneInstitutionalStorage {
    function setService(uint256 id, address service) external {
        _institutional().services[id] = service;
    }
}

/// @notice Regression guard for ERC-7201 layouts. `forge inspect` reports an empty
///         layout for namespaced contracts, so these tests are the only check that
///         each namespace resolves to the slot its identifier promises.
contract NamespaceSlotsTest is Test {
    function _erc7201(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_institutionalNamespace() public {
        InstitutionalStoreHarness h = new InstitutionalStoreHarness();
        address service = makeAddr("service");
        h.setService(7, service);
        // services is the first member, so the mapping is rooted at the namespace slot.
        bytes32 slot = keccak256(abi.encode(uint256(7), _erc7201("propane.storage.Institutional")));
        assertEq(address(uint160(uint256(vm.load(address(h), slot)))), service);
    }

    function test_complianceRegistryNamespace() public {
        RegistryStoreHarness h = new RegistryStoreHarness();
        address w = makeAddr("wallet");
        // records is the first member; WalletRecord.registered is the first field of the entry.
        bytes32 entry = keccak256(abi.encode(w, _erc7201("propane.storage.ComplianceRegistry")));
        assertEq(vm.load(address(h), entry), bytes32(0));
        h.register(w);
        assertEq(vm.load(address(h), entry), bytes32(uint256(1)));
    }
}
