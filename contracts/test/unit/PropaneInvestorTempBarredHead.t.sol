// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for the time-bounded bar head.
// @author adiii.eth
pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorTempBarredHead} from "../../src/compliance/heads/PropaneInvestorTempBarredHead.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";

contract PropaneInvestorTempBarredHeadTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    PropaneInvestorTempBarredHead internal head;

    event PropaneBarUpdated(address indexed wallet);

    function setUp() public override {
        super.setUp();
        head = PropaneInvestorTempBarredHead(
            _proxy(
                address(new PropaneInvestorTempBarredHead()),
                abi.encodeCall(PropaneInvestorTempBarredHead.initialize, (address(loc)))
            )
        );
        loc.setInstitutionalService(PropaneServices.SVC_BARRING_HEAD, address(head));
    }

    function _set(address caller, address wallet, uint64 until) internal {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(until, caller, address(head));
        vm.prank(caller);
        head.setBarredUntil(wallet, h, p);
    }

    function _blocked(address from, address to) internal returns (bool) {
        _nextBlock();
        vm.prank(address(engine));
        return decrypt(head.blocked(from, to));
    }

    function test_neverBarred_blocksNothing() public {
        assertFalse(_blocked(a, b));
    }

    function test_barsTheSender_notTheRecipient() public {
        _set(ta, a, uint64(block.timestamp + 1 days));
        assertTrue(_blocked(a, b));
        assertFalse(_blocked(b, a));
    }

    function test_barEndsExactlyAtItsTimestamp() public {
        uint64 until = uint64(block.timestamp + 1 days);
        _set(ta, a, until);
        vm.warp(until - 1);
        assertTrue(_blocked(a, b));
        vm.warp(until);
        assertFalse(_blocked(a, b));
    }

    function test_settingZero_liftsTheBar() public {
        _set(ta, a, uint64(block.timestamp + 1 days));
        _set(ta, a, 0);
        assertFalse(_blocked(a, b));
    }

    function test_setBarredUntil_emits() public {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(uint64(block.timestamp + 1), ta, address(head));
        vm.expectEmit(address(head));
        emit PropaneBarUpdated(a);
        vm.prank(ta);
        head.setBarredUntil(a, h, p);
    }

    function test_superOwnerMayBar() public {
        _set(address(this), a, uint64(block.timestamp + 1 days));
        assertTrue(_blocked(a, b));
    }

    function test_issuerAndOperatorMayNotBar() public {
        address[2] memory callers = [issuer, operator];
        for (uint256 i = 0; i < callers.length; i++) {
            (externalEuint64 h, bytes memory p) = encryptUint64(1, callers[i], address(head));
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, callers[i]));
            head.setBarredUntil(a, h, p);
        }
    }

    function test_onlyEngineReads() public {
        vm.prank(ta);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, ta));
        head.blocked(a, b);
    }
}
