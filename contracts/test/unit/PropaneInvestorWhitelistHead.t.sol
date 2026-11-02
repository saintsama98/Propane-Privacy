// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for the offering admission head.
// @author adiii.eth
pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorWhitelistHead} from "../../src/compliance/heads/PropaneInvestorWhitelistHead.sol";
import {externalEbool} from "encrypted-types/EncryptedTypes.sol";

contract PropaneInvestorWhitelistHeadTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    PropaneInvestorWhitelistHead internal head;

    event PropaneAdmissionUpdated(address indexed wallet);

    function setUp() public override {
        super.setUp();
        head = PropaneInvestorWhitelistHead(
            _proxy(
                address(new PropaneInvestorWhitelistHead()),
                abi.encodeCall(PropaneInvestorWhitelistHead.initialize, (address(loc)))
            )
        );
        loc.setInstitutionalService(PropaneServices.SVC_WHITELISTING_HEAD, address(head));
    }

    function _set(address caller, address wallet, bool admitted) internal {
        _nextBlock();
        (externalEbool h, bytes memory p) = encryptBool(admitted, caller, address(head));
        vm.prank(caller);
        head.setAdmitted(wallet, h, p);
    }

    function _blocked(address from, address to) internal returns (bool) {
        _nextBlock();
        vm.prank(address(engine));
        return decrypt(head.blocked(from, to));
    }

    function test_notAdmitted_isBlockedByDefault() public {
        assertTrue(_blocked(a, b));
    }

    function test_admissionAppliesToTheRecipientOnly() public {
        _set(issuer, b, true);
        assertFalse(_blocked(a, b), "sender need not be admitted");
        assertTrue(_blocked(b, a), "an admitted sender does not admit the recipient");
    }

    function test_revokingAdmission_blocksAgain() public {
        _set(issuer, b, true);
        _set(issuer, b, false);
        assertTrue(_blocked(a, b));
    }

    function test_transferAgentMayAdmit() public {
        _set(ta, b, true);
        assertFalse(_blocked(a, b));
    }

    function test_setAdmitted_emits() public {
        _nextBlock();
        (externalEbool h, bytes memory p) = encryptBool(true, issuer, address(head));
        vm.expectEmit(address(head));
        emit PropaneAdmissionUpdated(b);
        vm.prank(issuer);
        head.setAdmitted(b, h, p);
    }

    function test_operatorMayNotAdmit() public {
        (externalEbool h, bytes memory p) = encryptBool(true, operator, address(head));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, operator));
        head.setAdmitted(b, h, p);
    }

    function test_onlyEngineReads() public {
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, issuer));
        head.blocked(a, b);
    }
}
