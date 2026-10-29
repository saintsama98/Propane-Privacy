// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InvariantMaintainerHarness, MaintainerHandler} from "./handlers/MaintainerHandler.sol";

contract PropaneMaintainerInvariantsTest is Test {
    InvariantMaintainerHarness internal m;
    MaintainerHandler internal handler;

    function setUp() public {
        address root = makeAddr("root");
        InvariantMaintainerHarness impl = new InvariantMaintainerHarness();
        vm.prank(root);
        m = InvariantMaintainerHarness(address(new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, ()))));

        address[] memory actors = new address[](6);
        actors[0] = root;
        for (uint256 i = 1; i < actors.length; i++) {
            actors[i] = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
        }
        // Seed one holder of each delegated role so non-root paths are exercised.
        vm.startPrank(root);
        m.addUniversalRole(actors[1], m.OWNER());
        m.addUniversalRole(actors[2], m.PROPANE());
        m.addUniversalRole(actors[3], m.OFFICER());
        vm.stopPrank();

        handler = new MaintainerHandler(m, actors);
        targetContract(address(handler));
    }

    /// The recorded super owner always holds SUPER_OWNER, and no other actor does.
    function invariant_singleConsistentSuperOwner() public view {
        address so = m.superOwner();
        assertEq(m.getRoles(so), m.SUPER_OWNER());
        uint256 n = handler.actorCount();
        uint256 holders;
        for (uint256 i = 0; i < n; i++) {
            if (m.getRoles(handler.actors(i)) == m.SUPER_OWNER()) holders++;
        }
        assertEq(holders, 1);
    }

    /// Roles stay inside the declared set.
    function invariant_rolesInRange() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            assertLe(m.getRoles(handler.actors(i)), m.OFFICER());
        }
    }
}
