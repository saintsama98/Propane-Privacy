// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for the account-shape head.
// @author adiii.eth

pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorEOAHead} from "../../src/compliance/heads/PropaneInvestorEOAHead.sol";

contract PropaneInvestorEOAHeadTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");
    address internal vault;

    PropaneInvestorEOAHead internal head;

    function setUp() public override {
        super.setUp();
        vault = address(new CodeHolder());
        head = PropaneInvestorEOAHead(
            _proxy(
                address(new PropaneInvestorEOAHead()), abi.encodeCall(PropaneInvestorEOAHead.initialize, (address(loc)))
            )
        );
        loc.setInstitutionalService(PropaneServices.SVC_EOA_HEAD, address(head));
    }

    function _blocked(address from, address to) internal returns (bool) {
        _nextBlock();
        vm.prank(address(engine));
        return decrypt(head.blocked(from, to));
    }

    function test_eoaRecipient_isNotBlocked() public {
        assertFalse(_blocked(a, b));
    }

    function test_contractRecipient_isBlocked() public {
        assertTrue(_blocked(a, vault));
    }

    function test_contractSender_isNotBlocked() public {
        assertFalse(_blocked(vault, b));
    }

    function test_platformContractRecipient_isExempt() public {
        _nextBlock();
        vm.prank(operator);
        engine.setPlatformWallet(vault, true);
        assertFalse(_blocked(a, vault));
    }

    function test_onlyEngineReads() public {
        vm.prank(ta);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, ta));
        head.blocked(a, b);
    }
}

contract CodeHolder {}
