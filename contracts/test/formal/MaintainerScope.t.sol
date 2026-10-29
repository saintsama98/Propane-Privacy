// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PropaneMaintainer} from "../../src/maintainer/PropaneMaintainer.sol";

contract ScopeHarness is PropaneMaintainer {}

/// @notice Symbolic checks (halmos) of the role-management scope. Prefixed `check_`
///         so `forge test` ignores them; run with `halmos --match-contract MaintainerScope`.
contract MaintainerScopeTest is Test {
    ScopeHarness internal m;
    address internal constant ROOT = address(0x1000);
    address internal constant A = address(0x2000);
    address internal constant B = address(0x3000);

    function setUp() public {
        ScopeHarness impl = new ScopeHarness();
        vm.prank(ROOT);
        m = ScopeHarness(address(new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, ()))));
    }

    function _seed(uint8 roleA, uint8 roleB) internal {
        vm.assume(roleA >= 2 && roleA <= 4);
        vm.assume(roleB <= 4 && roleB != 1);
        vm.startPrank(ROOT);
        m.addUniversalRole(A, roleA);
        if (roleB != 0) m.addUniversalRole(B, roleB);
        vm.stopPrank();
    }

    /// Any add by a non-root holder leaves the root entry intact and grants only the caller's own role.
    function check_addScope(uint8 roleA, uint8 roleB, uint8 newRole, bool targetRoot) public {
        _seed(roleA, roleB);
        address target = targetRoot ? ROOT : B;
        vm.prank(A);
        try m.addUniversalRole(target, newRole) {
            assert(m.getRoles(ROOT) == 1);
            assert(m.superOwner() == ROOT);
            assert(m.getRoles(target) == roleA);
            assert(roleB == 0 || roleB == roleA);
        } catch {}
    }

    /// Any remove by a non-root holder only clears holders of the caller's own role.
    function check_removeScope(uint8 roleA, uint8 roleB, bool targetRoot) public {
        _seed(roleA, roleB);
        address target = targetRoot ? ROOT : B;
        vm.prank(A);
        try m.removeUniversalRole(target) {
            assert(!targetRoot);
            assert(roleB == roleA);
        } catch {}
        assert(m.getRoles(ROOT) == 1);
    }
}
