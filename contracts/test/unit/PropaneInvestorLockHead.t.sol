// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: unit tests for the issuance lock head.
// @author adiii.eth
pragma solidity 0.8.28;

import {PropaneFixture} from "../scenario/PropaneFixture.sol";
import {PropaneServiceConsumer} from "../../src/common/PropaneServiceConsumer.sol";
import {PropaneCodes} from "../../src/common/PropaneConstants.sol";
import {PropaneComplianceEngine} from "../../src/compliance/engine/PropaneComplianceEngine.sol";
import {ebool, euint64} from "encrypted-types/EncryptedTypes.sol";

contract PropaneInvestorLockHeadTest is PropaneFixture {
    uint64 internal constant US_LOCK = 365 days;
    uint64 internal constant NON_US_LOCK = 30 days;

    address internal a = makeAddr("a");
    address internal b = makeAddr("b");

    function setUp() public override {
        super.setUp();
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
    }

    function _setLocks(uint64 us, uint64 nonUS) internal {
        PropaneComplianceEngine.Config memory cfg = engine.config();
        cfg.periods.usLockPeriod = us;
        cfg.periods.nonUSLockPeriod = nonUS;
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.warp(block.timestamp + engine.CONFIG_DELAY());
        engine.applyConfig();
    }

    function test_noLockPeriods_recordsNothing() public {
        _issue(a, 100);
        assertEq(lockHead.openIssuances(a), 0);
        assertEq(_transfer(a, b, 100), 100);
    }

    function test_issuanceOpensARecord() public {
        _setLocks(US_LOCK, NON_US_LOCK);
        _issue(a, 100);
        assertEq(lockHead.openIssuances(a), 1);
        _issue(a, 100);
        assertEq(lockHead.openIssuances(a), 2);
    }

    function test_lockEndsExactlyAtItsPeriod() public {
        _setLocks(0, NON_US_LOCK);
        _issue(a, 100);
        uint256 end = block.timestamp + NON_US_LOCK;
        vm.warp(end - 1);
        assertEq(_transfer(a, b, 1), 0);
        assertEq(_code(a), PropaneCodes.CODE_HOLD_UP);
        vm.warp(end);
        assertEq(_transfer(a, b, 1), 1);
    }

    function test_recordStaysOpenUntilTheLongestLockEnds() public {
        _setLocks(US_LOCK, NON_US_LOCK);
        _issue(a, 100);
        vm.warp(block.timestamp + NON_US_LOCK);
        _issue(a, 100);
        assertEq(lockHead.openIssuances(a), 2, "the US lock is still running");
        vm.warp(block.timestamp + US_LOCK - NON_US_LOCK);
        _issue(a, 100);
        assertEq(lockHead.openIssuances(a), 2, "only the first record has fully expired");
    }

    function test_expiredRecordsFreeTheCap() public {
        _setLocks(0, NON_US_LOCK);
        uint256 max = lockHead.MAX_OPEN_ISSUANCES();
        for (uint256 i = 0; i < max; i++) {
            _issue(a, 1);
        }
        assertEq(lockHead.openIssuances(a), max);
        vm.warp(block.timestamp + NON_US_LOCK);
        _issue(a, 1);
        assertEq(lockHead.openIssuances(a), 1);
    }

    function test_recordsArePerWallet() public {
        _setLocks(0, NON_US_LOCK);
        _issue(a, 100);
        assertEq(lockHead.openIssuances(b), 0);
    }

    function test_onlyEngineRecords() public {
        vm.prank(ta);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, ta));
        lockHead.recordIssuance(a, euint64.wrap(bytes32(0)));
    }

    function test_onlyEngineReads() public {
        vm.prank(ta);
        vm.expectRevert(abi.encodeWithSelector(PropaneServiceConsumer.PropaneUnauthorized.selector, ta));
        lockHead.lockedFails(a, ebool.wrap(bytes32(0)), euint64.wrap(bytes32(0)), euint64.wrap(bytes32(0)));
    }
}
