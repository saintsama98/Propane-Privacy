// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {IPropaneComplianceRegistry} from "../../src/registry/IPropaneComplianceRegistry.sol";
import {PropaneComplianceRegistry} from "../../src/registry/PropaneComplianceRegistry.sol";
import {PropaneComplianceEngine} from "../../src/compliance/engine/PropaneComplianceEngine.sol";
import {PropaneCensus} from "../../src/compliance/census/PropaneCensus.sol";
import {PropaneInvestorLockHead} from "../../src/compliance/heads/PropaneInvestorLockHead.sol";
import {PropaneInstitutional} from "../../src/institution/PropaneInstitutional.sol";
import {PropaneSecurityToken} from "../../src/security/PropaneSecurityToken.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";

/// @notice Every custom error outside the maintainer, raised through the deployed system.
contract ErrorsTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    function test_registry_zeroWallet() public {
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(OTHER, 0, false, false, false);
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneZeroWallet.selector);
        registry.registerWallet(address(0), i, proof);
    }

    function test_registry_alreadyRegistered() public {
        _register(a, OTHER, 0, false, false);
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(OTHER, 0, false, false, false);
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneAlreadyRegistered.selector);
        registry.registerWallet(a, i, proof);
    }

    function test_registry_notRegistered() public {
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneNotRegistered.selector);
        registry.deregisterWallet(a);
    }

    function test_census_notRecomputing() public {
        vm.expectRevert(PropaneCensus.PropaneNotRecomputing.selector);
        census.continueRecompute(1);
    }

    function test_engine_tooManyEUSlots() public {
        PropaneComplianceEngine.Config memory cfg = engine.config();
        cfg.limits.euCountrySlots = engine.MAX_EU_SLOTS() + 1;
        vm.prank(issuer);
        vm.expectRevert(PropaneComplianceEngine.PropaneTooManyEUSlots.selector);
        engine.scheduleConfig(cfg);
    }

    function test_engine_euSlotsCannotShrink() public {
        PropaneComplianceEngine.Config memory cfg = engine.config();
        cfg.limits.euCountrySlots = 2;
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.warp(block.timestamp + engine.CONFIG_DELAY());
        engine.applyConfig();

        cfg.limits.euCountrySlots = 1;
        vm.prank(issuer);
        vm.expectRevert(PropaneComplianceEngine.PropaneEUSlotsCannotShrink.selector);
        engine.scheduleConfig(cfg);
    }

    function test_locator_zeroMaintainer() public {
        vm.expectRevert(PropaneInstitutional.PropaneZeroMaintainer.selector);
        loc.setInstitutionalService(PropaneServices.SVC_ROLES, address(0));
    }

    function test_consumer_zeroLocator() public {
        address impl = address(new PropaneCensus());
        vm.expectRevert(PropaneServiceConsumer.PropaneZeroLocator.selector);
        new ERC1967Proxy(impl, abi.encodeCall(PropaneCensus.initialize, (address(0))));
    }

    function test_lockHead_tooManyOpenIssuances() public {
        PropaneComplianceEngine.Config memory cfg = engine.config();
        cfg.periods.nonUSLockPeriod = 365 days;
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.warp(block.timestamp + engine.CONFIG_DELAY());
        engine.applyConfig();

        _register(a, OTHER, 0, false, false);
        uint256 max = lockHead.MAX_OPEN_ISSUANCES();
        for (uint256 n = 0; n < max; n++) {
            _issue(a, 1);
        }
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(1, issuer, address(token));
        vm.prank(issuer);
        vm.expectRevert(PropaneInvestorLockHead.PropaneTooManyOpenIssuances.selector);
        token.issue(a, h, p);
    }

    function test_token_sameAccount() public {
        _register(a, OTHER, 0, false, false);
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(1, ta, address(token));
        vm.prank(ta);
        vm.expectRevert(PropaneSecurityToken.PropaneSameAccount.selector);
        token.forcedTransfer(a, a, h, p);
    }

    function test_token_amountNotAllowed() public {
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        vm.prank(a);
        vm.expectRevert(PropaneSecurityToken.PropaneAmountNotAllowed.selector);
        token.confidentialTransfer(b, euint64.wrap(bytes32(uint256(1))));
    }
}
