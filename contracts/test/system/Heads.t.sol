// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneServices, PropaneCodes} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorBlacklistHead} from "../../src/compliance/dependency/heads/propaneInvestorBlacklistHead.sol";
import {PropaneInvestorTempBarredHead} from "../../src/compliance/dependency/heads/propaneInvestorTempBarredHead.sol";
import {PropaneInvestorWhitelistHead} from "../../src/compliance/dependency/heads/propaneInvestorWhitelistHead.sol";
import {PropaneInvestorEOAHead} from "../../src/compliance/dependency/heads/propaneInvestorEOAHead.sol";
import {externalEbool, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

contract HeadsTest is PropaneFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    PropaneInvestorBlacklistHead internal blacklist;
    PropaneInvestorTempBarredHead internal barring;
    PropaneInvestorWhitelistHead internal whitelist;
    PropaneInvestorEOAHead internal eoa;

    function setUp() public override {
        super.setUp();
        _register(alice, OTHER, 0, false, false);
        _register(bob, OTHER, 0, false, false);
        _issue(alice, 100);
    }

    function _wire(uint256 id, address impl) internal returns (address p) {
        p = _proxy(impl, abi.encodeWithSignature("initialize(address)", address(loc)));
        loc.setInstitutionalService(id, p);
    }

    function test_blacklistBlocksRecipient_andSender() public {
        blacklist = PropaneInvestorBlacklistHead(
            _wire(PropaneServices.SVC_BLACKLISTING_HEAD, address(new PropaneInvestorBlacklistHead()))
        );
        _list(bob, true);
        assertEq(_transfer(alice, bob, 10), 0);
        assertEq(_code(alice), PropaneCodes.CODE_HEAD_BLOCKED);
        _list(bob, false);
        _list(alice, true);
        assertEq(_transfer(alice, bob, 10), 0, "a listed sender is blocked: sanctions override exit");
        _list(alice, false);
        assertEq(_transfer(alice, bob, 10), 10);
    }

    function test_tempBarExpires() public {
        barring = PropaneInvestorTempBarredHead(
            _wire(PropaneServices.SVC_BARRING_HEAD, address(new PropaneInvestorTempBarredHead()))
        );
        (externalEuint64 h, bytes memory p) = encryptUint64(uint64(block.timestamp + 7 days), ta, address(barring));
        _nextBlock();
        vm.prank(ta);
        barring.setBarredUntil(alice, h, p);
        assertEq(_transfer(alice, bob, 10), 0);
        assertEq(_code(alice), PropaneCodes.CODE_HEAD_BLOCKED);
        vm.warp(block.timestamp + 8 days);
        assertEq(_transfer(alice, bob, 10), 10);
    }

    function test_whitelistRequiresAdmission() public {
        whitelist = PropaneInvestorWhitelistHead(
            _wire(PropaneServices.SVC_WHITELISTING_HEAD, address(new PropaneInvestorWhitelistHead()))
        );
        assertEq(_transfer(alice, bob, 10), 0, "not admitted by default");
        (externalEbool h, bytes memory p) = encryptBool(true, issuer, address(whitelist));
        _nextBlock();
        vm.prank(issuer);
        whitelist.setAdmitted(bob, h, p);
        assertEq(_transfer(alice, bob, 10), 10);
    }

    function test_eoaHeadBlocksContractRecipientUnlessPlatform() public {
        eoa = PropaneInvestorEOAHead(_wire(PropaneServices.SVC_EOA_HEAD, address(new PropaneInvestorEOAHead())));
        address vault = address(new Dummy());
        _register(vault, OTHER, 0, false, false);
        assertEq(_transfer(alice, vault, 10), 0);
        assertEq(_code(alice), PropaneCodes.CODE_HEAD_BLOCKED);
        assertEq(_transfer(alice, bob, 10), 10);
        _nextBlock();
        vm.prank(operator);
        engine.setPlatformWallet(vault, true);
        assertEq(_transfer(alice, vault, 10), 10, "platform wallets are exempt");
    }

    /// @dev A head's result is granted to its caller; if anyone could call it, any contract could
    ///      re-grant the flag to itself and decrypt it: an attribute oracle (Note 05, R7).
    function test_headsAnswerOnlyTheEngine() public {
        blacklist = PropaneInvestorBlacklistHead(
            _wire(PropaneServices.SVC_BLACKLISTING_HEAD, address(new PropaneInvestorBlacklistHead()))
        );
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, address(this)));
        blacklist.blocked(alice, bob);
    }

    function test_onlyTransferAgentListsInvestors() public {
        blacklist = PropaneInvestorBlacklistHead(
            _wire(PropaneServices.SVC_BLACKLISTING_HEAD, address(new PropaneInvestorBlacklistHead()))
        );
        (externalEbool h, bytes memory p) = encryptBool(true, issuer, address(blacklist));
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, issuer));
        blacklist.setBlacklisted(bob, h, p);
    }

    function _list(address who, bool v) internal {
        (externalEbool h, bytes memory p) = encryptBool(v, ta, address(blacklist));
        _nextBlock();
        vm.prank(ta);
        blacklist.setBlacklisted(who, h, p);
    }
}

contract Dummy {}
