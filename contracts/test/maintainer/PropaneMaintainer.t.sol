// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PropaneMaintainer} from "../../src/maintainer/propaneMaintainer.sol";

contract MaintainerHarness is PropaneMaintainer {}

contract PropaneMaintainerTest is Test {
    MaintainerHarness internal m;

    address internal propane = makeAddr("propane");
    address internal officer = makeAddr("officer");
    address internal owner_ = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        MaintainerHarness impl = new MaintainerHarness();
        m = MaintainerHarness(address(new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, ()))));
        m.addUniversalRole(propane, m.PROPANE());
        m.addUniversalRole(officer, m.OFFICER());
        m.addUniversalRole(owner_, m.OWNER());
    }

    function test_initialState() public view {
        assertEq(m.superOwner(), address(this));
        assertEq(m.getRoles(address(this)), m.SUPER_OWNER());
    }

    // --- W0 regression: privilege escalation through addUniversalRole ---

    function test_officerCannotGrantOwner() public {
        uint8 role = m.OWNER();
        vm.prank(officer);
        vm.expectRevert();
        m.addUniversalRole(stranger, role);
    }

    function test_officerCannotGrantPropane() public {
        uint8 role = m.PROPANE();
        vm.prank(officer);
        vm.expectRevert();
        m.addUniversalRole(stranger, role);
    }

    function test_officerCannotOverwriteSuperOwner() public {
        uint8 role = m.OFFICER();
        vm.prank(officer);
        vm.expectRevert();
        m.addUniversalRole(address(this), role);
        assertEq(m.getRoles(m.superOwner()), m.SUPER_OWNER());
    }

    function test_propaneCannotOverwriteSuperOwner() public {
        uint8 role = m.PROPANE();
        vm.prank(propane);
        vm.expectRevert();
        m.addUniversalRole(address(this), role);
    }

    function test_superOwnerCannotDemoteSelfThroughAdd() public {
        uint8 role = m.OFFICER();
        vm.expectRevert();
        m.addUniversalRole(address(this), role);
    }

    function test_officerCannotRewriteOwner() public {
        uint8 role = m.OFFICER();
        vm.prank(officer);
        vm.expectRevert();
        m.addUniversalRole(owner_, role);
    }

    function test_officerCannotRemovePropane() public {
        vm.prank(officer);
        vm.expectRevert();
        m.removeUniversalRole(propane);
    }

    // --- intended behaviour that must survive the fix ---

    function test_superOwnerGrantsEveryNonRootRole() public {
        address a = makeAddr("a");
        m.addUniversalRole(a, m.OWNER());
        assertEq(m.getRoles(a), m.OWNER());
    }

    function test_officerManagesOfficers() public {
        uint8 role = m.OFFICER();
        vm.prank(officer);
        m.addUniversalRole(stranger, role);
        assertEq(m.getRoles(stranger), role);
        vm.prank(officer);
        m.removeUniversalRole(stranger);
        assertEq(m.getRoles(stranger), m.NO_ROLE());
    }

    function test_strangerCannotGrant() public {
        uint8 role = m.OFFICER();
        vm.prank(stranger);
        vm.expectRevert();
        m.addUniversalRole(stranger, role);
    }

    function test_superOwnerCannotBeRemoved() public {
        vm.expectRevert();
        m.removeUniversalRole(address(this));
    }

    function test_transferSuperOwner() public {
        address next = makeAddr("next");
        m.transferSuperOwner(next);
        assertEq(m.superOwner(), next);
        assertEq(m.getRoles(next), m.SUPER_OWNER());
        assertEq(m.getRoles(address(this)), m.NO_ROLE());
    }

    function test_maintainerNamespaceSlot() public pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("propane.storage.Maintainer")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(expected, 0xecd650e130efcdb91f813bdd8d63149ee409488eac16480924c5e3846af82f00);
    }
}
