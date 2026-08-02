// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PropaneStorageProbe} from "../src/PropaneStorageProbe.sol";

/// @dev Bucket 0 acceptance. Proves the toolchain and the storage convention,
///      nothing about the system itself.
contract ProbeV2 is PropaneStorageProbe {
    /// @custom:storage-location erc7201:propane.storage.ProbeV2
    struct ProbeV2Storage {
        uint256 added;
        address alsoAdded;
    }

    // erc7201("propane.storage.ProbeV2")
    bytes32 private constant PROBE_V2_STORAGE =
        keccak256(abi.encode(uint256(keccak256("propane.storage.ProbeV2")) - 1)) & ~bytes32(uint256(0xff));

    function _v2() private pure returns (ProbeV2Storage storage $) {
        bytes32 s = PROBE_V2_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function setAdded(uint256 a, address b) external {
        _v2().added = a;
        _v2().alsoAdded = b;
    }

    function added() external view returns (uint256) {
        return _v2().added;
    }
}

contract Bucket0Test is Test {
    PropaneStorageProbe internal probe;

    function setUp() public {
        PropaneStorageProbe impl = new PropaneStorageProbe();
        bytes memory init = abi.encodeCall(PropaneStorageProbe.initialize, (4242));
        probe = PropaneStorageProbe(address(new ERC1967Proxy(address(impl), init)));
    }

    /// @notice The namespace constant must equal the ERC-7201 formula, computed
    ///         here from the string rather than copied from the contract.
    function test_erc7201SlotMatchesSpec() public view {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("propane.storage.Probe")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(probe.slot(), expected, "namespace slot deviates from erc7201 formula");
        // Independently cross-checked with `cast keccak` outside Solidity.
        assertEq(probe.slot(), 0xc44bfc103803616d465b949e3657ad4ff52fb2d675e378f976bd05669b5f4700);
    }

    /// @notice Low 8 bits must be zero per the spec's `& ~0xff` masking.
    function test_slotIsAlignedTo256() public view {
        assertEq(uint256(probe.slot()) & 0xff, 0, "namespace not aligned to 256");
    }

    /// @notice Namespaces must not collide with Solidity's own slot derivation.
    function test_namespaceIsDisjointFromSequentialSlots() public view {
        for (uint256 i = 0; i < 128; i++) {
            assertTrue(probe.slot() != bytes32(i), "namespace collides with a sequential slot");
        }
    }

    /// @notice THE bucket-0 deliverable: upgrade to a v2 that adds state and
    ///         prove pre-existing values are untouched.
    function test_upgradePreservesStorage() public {
        assertEq(probe.value(), 4242);
        bytes32 slotBefore = probe.slot();

        ProbeV2 v2impl = new ProbeV2();
        probe.upgradeToAndCall(address(v2impl), "");

        // Pre-existing namespace survived the implementation swap.
        assertEq(probe.value(), 4242, "value shifted across upgrade");
        assertEq(probe.slot(), slotBefore, "namespace moved across upgrade");

        // New state in a new namespace does not disturb the old one.
        ProbeV2(address(probe)).setAdded(7, address(0xBEEF));
        assertEq(ProbeV2(address(probe)).added(), 7);
        assertEq(probe.value(), 4242, "adding v2 state corrupted v1 state");
    }

    /// @notice Raw slot read: the value lives exactly where the formula says.
    function test_valueIsStoredAtTheNamespaceSlot() public view {
        bytes32 raw = vm.load(address(probe), probe.slot());
        assertEq(uint256(raw), 4242, "value is not at the namespace slot");
    }
}
