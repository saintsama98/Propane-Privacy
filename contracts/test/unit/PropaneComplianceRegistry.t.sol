// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for each path through the compliance registry.
// @author adiii.eth

pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {IPropaneComplianceRegistry} from "../../src/registry/IPropaneComplianceRegistry.sol";
import {PropaneComplianceRegistry} from "../../src/registry/PropaneComplianceRegistry.sol";
import {PropaneAttributes} from "../../src/interfaces/IPropaneServices.sol";
import {ebool, euint8} from "encrypted-types/EncryptedTypes.sol";

contract PropaneComplianceRegistryTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    event PropaneWalletRegistered(address indexed wallet);
    event PropaneAttributesUpdated(address indexed wallet);
    event PropaneWalletDeregistered(address indexed wallet);

    function _assertAttrs(address w, uint8 region, uint8 euCountry, bool acc, bool qual, bool liq) internal {
        PropaneAttributes memory attrs = registry.attributes(w);
        assertEq(decrypt(attrs.region), region, "region");
        assertEq(decrypt(attrs.euCountry), euCountry, "euCountry");
        assertEq(decrypt(attrs.accredited), acc, "accredited");
        assertEq(decrypt(attrs.qualified), qual, "qualified");
        assertEq(decrypt(attrs.liquidateOnly), liq, "liquidateOnly");
    }

    function test_register_storesTheRecord() public {
        assertFalse(registry.isRegistered(a));
        _register(a, EU, 2, true, false, true);
        assertTrue(registry.isRegistered(a));
        assertEq(registry.walletCount(), 1);
        assertEq(registry.walletAt(0), a);
        _assertAttrs(a, EU, 2, true, false, true);
    }

    function test_register_emits() public {
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(OTHER, 0, false, false, false);
        vm.expectEmit(address(registry));
        emit PropaneWalletRegistered(a);
        vm.prank(ta);
        registry.registerWallet(a, i, proof);
    }

    function test_register_grantsEveryReader() public {
        _register(a, US, 0, true, false);
        PropaneAttributes memory attrs = registry.attributes(a);
        bytes32[5] memory handles = [
            euint8.unwrap(attrs.region),
            euint8.unwrap(attrs.euCountry),
            ebool.unwrap(attrs.accredited),
            ebool.unwrap(attrs.qualified),
            ebool.unwrap(attrs.liquidateOnly)
        ];
        for (uint256 k = 0; k < handles.length; k++) {
            assertTrue(_allowed(handles[k], address(registry)), "registry");
            assertTrue(_allowed(handles[k], address(engine)), "engine");
            assertTrue(_allowed(handles[k], address(census)), "census");
            assertTrue(_allowed(handles[k], keeper), "record keeper");
            assertFalse(_allowed(handles[k], a), "the wallet itself");
            assertFalse(_allowed(handles[k], issuer), "the issuer");
        }
    }

    function test_update_replacesTheRecord() public {
        _register(a, EU, 2, true, false);
        _update(a, US, 0, false, true);
        _assertAttrs(a, US, 0, false, true, false);
        assertEq(registry.walletCount(), 1);
    }

    function test_update_emits() public {
        _register(a, OTHER, 0, false, false);
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(US, 0, false, false, false);
        vm.expectEmit(address(registry));
        emit PropaneAttributesUpdated(a);
        vm.prank(ta);
        registry.updateAttributes(a, i, proof);
    }

    function test_update_unknownWalletReverts() public {
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(US, 0, false, false, false);
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneNotRegistered.selector);
        registry.updateAttributes(a, i, proof);
    }

    function test_update_deregisteredWalletReverts() public {
        _register(a, OTHER, 0, false, false);
        vm.prank(ta);
        registry.deregisterWallet(a);
        _nextBlock();
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(US, 0, false, false, false);
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneNotRegistered.selector);
        registry.updateAttributes(a, i, proof);
    }

    function test_deregister_keepsTheAttributes() public {
        _register(a, JP, 0, false, true);
        vm.expectEmit(address(registry));
        emit PropaneWalletDeregistered(a);
        vm.prank(ta);
        registry.deregisterWallet(a);
        assertFalse(registry.isRegistered(a));
        _assertAttrs(a, JP, 0, false, true, false);
    }

    function test_deregister_twiceReverts() public {
        _register(a, OTHER, 0, false, false);
        vm.prank(ta);
        registry.deregisterWallet(a);
        vm.prank(ta);
        vm.expectRevert(PropaneComplianceRegistry.PropaneNotRegistered.selector);
        registry.deregisterWallet(a);
    }

    function test_reregister_doesNotListTheWalletTwice() public {
        _register(a, OTHER, 0, false, false);
        vm.prank(ta);
        registry.deregisterWallet(a);
        _register(a, US, 0, true, false);
        assertTrue(registry.isRegistered(a));
        assertEq(registry.walletCount(), 1);
        _assertAttrs(a, US, 0, true, false, false);
    }

    function test_walletAt_keepsRegistrationOrder() public {
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        assertEq(registry.walletCount(), 2);
        assertEq(registry.walletAt(0), a);
        assertEq(registry.walletAt(1), b);
        vm.expectRevert();
        registry.walletAt(2);
    }

    function test_regrant_givesTheNewEngineAccess() public {
        _register(a, OTHER, 0, false, false);
        address newEngine = makeAddr("newEngine");
        PropaneAttributes memory attrs = registry.attributes(a);
        assertFalse(_allowed(euint8.unwrap(attrs.region), newEngine));

        loc.setInstitutionalService(PropaneServices.SVC_COMPLIANCE, newEngine);
        address[] memory wallets = new address[](2);
        wallets[0] = a;
        wallets[1] = b; // never registered: skipped, no revert
        _nextBlock();
        vm.prank(ta);
        registry.regrantCompliance(wallets);

        assertTrue(_allowed(euint8.unwrap(attrs.region), newEngine));
        assertTrue(_allowed(euint8.unwrap(attrs.euCountry), newEngine));
        assertTrue(_allowed(ebool.unwrap(attrs.accredited), newEngine));
        assertTrue(_allowed(ebool.unwrap(attrs.qualified), newEngine));
        assertTrue(_allowed(ebool.unwrap(attrs.liquidateOnly), newEngine));
    }

    function test_superOwnerMayDeregister() public {
        _register(a, OTHER, 0, false, false);
        registry.deregisterWallet(a);
        assertFalse(registry.isRegistered(a));
    }

    function test_onlyOfficerOrSuperOwnerWrites() public {
        _register(a, OTHER, 0, false, false);
        address[3] memory callers = [issuer, operator, b];
        address[] memory wallets = new address[](0);
        (IPropaneComplianceRegistry.EncryptedAttributesInput memory i, bytes memory proof) =
            _attrInput(OTHER, 0, false, false, false);
        for (uint256 k = 0; k < callers.length; k++) {
            bytes memory denied =
                abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, callers[k]);
            vm.prank(callers[k]);
            vm.expectRevert(denied);
            registry.registerWallet(b, i, proof);
            vm.prank(callers[k]);
            vm.expectRevert(denied);
            registry.updateAttributes(a, i, proof);
            vm.prank(callers[k]);
            vm.expectRevert(denied);
            registry.deregisterWallet(a);
            vm.prank(callers[k]);
            vm.expectRevert(denied);
            registry.regrantCompliance(wallets);
        }
    }
}
