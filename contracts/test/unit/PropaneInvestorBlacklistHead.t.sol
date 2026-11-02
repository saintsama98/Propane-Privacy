// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for the encrypted deny list head.
// @author adiii.eth

pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorBlacklistHead} from "../../src/compliance/heads/PropaneInvestorBlacklistHead.sol";
import {externalEbool} from "encrypted-types/EncryptedTypes.sol";

contract PropaneInvestorBlacklistHeadTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    PropaneInvestorBlacklistHead internal head;

    event PropaneBlacklistUpdated(address indexed wallet);

    function setUp() public override {
        super.setUp();
        head = PropaneInvestorBlacklistHead(
            _proxy(
                address(new PropaneInvestorBlacklistHead()),
                abi.encodeCall(PropaneInvestorBlacklistHead.initialize, (address(loc)))
            )
        );
        loc.setInstitutionalService(PropaneServices.SVC_BLACKLISTING_HEAD, address(head));
    }

    function _set(address caller, address wallet, bool listed) internal {
        _nextBlock();
        (externalEbool h, bytes memory p) = encryptBool(listed, caller, address(head));
        vm.prank(caller);
        head.setBlacklisted(wallet, h, p);
    }

    function _blocked(address from, address to) internal returns (bool) {
        _nextBlock();
        vm.prank(address(engine));
        return decrypt(head.blocked(from, to));
    }

    function test_nothingListed_blocksNothing() public {
        assertFalse(_blocked(a, b));
    }

    function test_listedSender_isBlocked() public {
        _set(ta, a, true);
        assertTrue(_blocked(a, b));
    }

    function test_listedRecipient_isBlocked() public {
        _set(ta, b, true);
        assertTrue(_blocked(a, b));
    }

    function test_bothListed_isBlocked() public {
        _set(ta, a, true);
        _set(ta, b, true);
        assertTrue(_blocked(a, b));
    }

    function test_unlisting_clearsTheBlock() public {
        _set(ta, a, true);
        _set(ta, a, false);
        assertFalse(_blocked(a, b));
    }

    function test_setBlacklisted_emits() public {
        _nextBlock();
        (externalEbool h, bytes memory p) = encryptBool(true, ta, address(head));
        vm.expectEmit(address(head));
        emit PropaneBlacklistUpdated(a);
        vm.prank(ta);
        head.setBlacklisted(a, h, p);
    }

    function test_superOwnerMayList() public {
        _set(address(this), a, true);
        assertTrue(_blocked(a, b));
    }

    function test_issuerAndOperatorMayNotList() public {
        address[2] memory callers = [issuer, operator];
        for (uint256 i = 0; i < callers.length; i++) {
            (externalEbool h, bytes memory p) = encryptBool(true, callers[i], address(head));
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, callers[i]));
            head.setBlacklisted(a, h, p);
        }
    }

    function test_onlyEngineReads() public {
        vm.prank(ta);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, ta));
        head.blocked(a, b);
    }
}
