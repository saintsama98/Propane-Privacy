// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/engine/PropaneComplianceEngine.sol";
import {PropaneCensus} from "../../src/compliance/census/PropaneCensus.sol";
import {PropaneSecurityToken} from "../../src/security/PropaneSecurityToken.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradesTest is PropaneFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function test_onlySuperOwnerUpgrades() public {
        address impl = address(new PropaneComplianceEngine());
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, issuer));
        UUPSUpgradeable(address(engine)).upgradeToAndCall(impl, "");
        UUPSUpgradeable(address(engine)).upgradeToAndCall(impl, "");
    }

    function test_upgradePreservesStateAndCensus() public {
        _register(alice, US, 0, true, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
        _transfer(alice, bob, 40);
        UUPSUpgradeable(address(token)).upgradeToAndCall(address(new PropaneSecurityToken()), "");
        UUPSUpgradeable(address(census)).upgradeToAndCall(address(new PropaneCensus()), "");
        UUPSUpgradeable(address(engine)).upgradeToAndCall(address(new PropaneComplianceEngine()), "");
        assertEq(_bal(alice), 60);
        assertEq(_bal(bob), 40);
        assertEq(_transfer(bob, alice, 40), 40);
        _assertCensus();
    }

    function test_implementationsCannotBeInitialized() public {
        PropaneComplianceEngine impl = new PropaneComplianceEngine();
        PropaneComplianceEngine.Config memory cfg;
        vm.expectRevert();
        impl.initialize(address(loc), cfg);
    }

    /// @notice Replacing the compliance service is a deployment decision (the swap pattern). The
    ///         new engine must be re-granted access to existing balances and attributes.
    function test_complianceSwapWithRegrant() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
        PropaneComplianceEngine.Config memory cfg = engine.config();
        PropaneComplianceEngine next = PropaneComplianceEngine(
            _proxy(
                address(new PropaneComplianceEngine()),
                abi.encodeCall(PropaneComplianceEngine.initialize, (address(loc), cfg))
            )
        );
        loc.setInstitutionalService(PropaneServices.SVC_COMPLIANCE, address(next));
        engine = next;
        address[] memory ws = new address[](2);
        ws[0] = alice;
        ws[1] = bob;
        _nextBlock();
        vm.prank(ta);
        token.regrantCompliance(ws);
        _nextBlock();
        vm.prank(ta);
        registry.regrantCompliance(ws);
        assertEq(_transfer(alice, bob, 10), 10);
    }

    function test_onlyOperatorOrRootWiresServices() public {
        vm.prank(issuer);
        vm.expectRevert("Not enough permissions");
        loc.setInstitutionalService(PropaneServices.SVC_COMPLIANCE, address(0xdead));
        vm.prank(operator);
        vm.expectRevert("Not enough permissions");
        loc.setInstitutionalService(PropaneServices.SVC_ROLES, address(0xdead));
    }
}
