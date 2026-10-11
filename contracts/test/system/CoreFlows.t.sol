// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/orbex/propaneEngine.sol";
import {PropaneSecurityToken} from "../../src/security/propaneSecurityToken.sol";
import {PropaneCodes} from "../../src/common/PropaneConstants.sol";

contract CoreFlowsTest is PropaneFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function test_issueAndTransfer() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        assertEq(_issue(alice, 100), 100);
        assertEq(_transfer(alice, bob, 40), 40);
        assertEq(_bal(alice), 60);
        assertEq(_bal(bob), 40);
        assertEq(_code(alice), PropaneCodes.CODE_VALID);
        _assertCensus();
        assertEq(_counters()[0], 2);
    }

    function test_fullExitAndReentryKeepCensusExact() public {
        _register(alice, US, 0, true, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
        _assertCensus();
        // Flowback is closed in the default config, so US -> non-US is unrestricted.
        _transfer(alice, bob, 100);
        _assertCensus();
        assertEq(_counters()[2], 0); // US counter back to zero after the US holder left
    }

    function test_unregisteredReceiverReverts() public {
        _register(alice, OTHER, 0, false, false);
        _issue(alice, 10);
        (bytes32 h, bytes memory p) = _enc(alice, 5);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PropaneSecurityToken.PropaneInvalidReceiver.selector, carol));
        token.confidentialTransfer(carol, _ext(h), p);
    }

    function test_insufficientBalanceMovesZeroWithoutRevert() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 10);
        assertEq(_transfer(alice, bob, 11), 0);
        assertEq(_bal(alice), 10);
        assertEq(_bal(bob), 0);
        assertEq(_code(alice), PropaneCodes.CODE_NOT_ENOUGH_TOKENS);
        _assertCensus();
    }

    function test_forbiddenDestination() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, FORBIDDEN, 0, false, false);
        _issue(alice, 10);
        assertEq(_transfer(alice, bob, 5), 0);
        assertEq(_code(alice), PropaneCodes.CODE_DESTINATION_RESTRICTED);
    }

    function test_liquidateOnlyRecipient() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false, true);
        _issue(alice, 10);
        assertEq(_transfer(alice, bob, 5), 0);
        assertEq(_code(alice), PropaneCodes.CODE_LIQUIDATE_ONLY);
    }

    function test_freezeLimitsAvailable() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
        _freeze(alice, 50);
        assertEq(_transfer(alice, bob, 60), 0);
        assertEq(_code(alice), PropaneCodes.CODE_NOT_ENOUGH_TOKENS);
        assertEq(_transfer(alice, bob, 50), 50);
    }

    function test_forcedTransferBypassesFreezeAndUpdatesCensus() public {
        _register(alice, US, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
        _freeze(alice, 100);
        assertEq(_forced(alice, bob, 100), 100);
        assertEq(_bal(alice), 0);
        assertEq(_bal(bob), 100);
        assertEq(decrypt(token.getFrozenTokens(alice)), 0); // clamped to the new balance
        _assertCensus();
    }

    function test_seizureIntoTreasuryIsRecordedAsExit() public {
        _register(alice, JP, 0, false, false);
        _issue(alice, 100);
        assertEq(_counters()[4], 1);
        assertEq(_forced(alice, treasury, 100), 100);
        assertEq(_counters()[4], 0);
        assertEq(_counters()[0], 0);
        _assertCensus();
    }

    function test_burnFullBalanceLeavesCensus() public {
        _register(alice, OTHER, 0, false, false);
        _issue(alice, 100);
        assertEq(_burn(alice, 101), 0); // over-burn moves nothing
        assertEq(_burn(alice, 100), 100);
        assertEq(_counters()[0], 0);
        assertEq(decrypt(token.confidentialTotalSupply()), 0);
    }

    function test_attributeChangeMovesHolderBetweenCounters() public {
        _register(alice, US, 0, true, false);
        _issue(alice, 100);
        assertEq(_counters()[2], 1);
        assertEq(_counters()[3], 1);
        _update(alice, JP, 0, false, false);
        _assertCensus();
        assertEq(_counters()[0], 1);
        assertEq(_counters()[2], 0);
        assertEq(_counters()[4], 1);
    }

    /// @dev Regression: a full-balance self-transfer must not count the holder as leaving.
    function test_selfTransferOfFullBalanceKeepsHolderCounted() public {
        _register(alice, US, 0, true, false);
        _issue(alice, 100);
        assertEq(_transfer(alice, alice, 100), 100);
        assertEq(_bal(alice), 100);
        _assertCensus();
        assertEq(_counters()[0], 1);
    }

    function test_pausedTokenReverts() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 10);
        vm.prank(ta);
        token.setPaused(true);
        (bytes32 h, bytes memory p) = _enc(alice, 5);
        vm.prank(alice);
        vm.expectRevert(PropaneSecurityToken.PropaneTokenPaused.selector);
        token.confidentialTransfer(bob, _ext(h), p);
    }

    function test_senderExitAfterDeregistration() public {
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 10);
        vm.prank(ta);
        registry.deregisterWallet(alice);
        assertEq(_transfer(alice, bob, 10), 10); // an ineligible holder can still exit
        _assertCensus();
    }

    // ------------------------------------------------------------ helpers

    function _enc(address user, uint64 v) internal returns (bytes32, bytes memory) {
        (externalEuint64Alias h, bytes memory p) = _encAlias(user, v);
        return (externalEuint64Alias.unwrap(h), p);
    }

    type externalEuint64Alias is bytes32;

    function _encAlias(address user, uint64 v) internal returns (externalEuint64Alias, bytes memory) {
        (externalEuint64 h, bytes memory p) = encryptUint64(v, user, address(token));
        return (externalEuint64Alias.wrap(externalEuint64.unwrap(h)), p);
    }

    function _ext(bytes32 h) internal pure returns (externalEuint64) {
        return externalEuint64.wrap(h);
    }
}

import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
