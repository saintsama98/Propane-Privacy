// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PropaneFixture} from "./PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/orbex/propaneEngine.sol";
import {PropaneCodes} from "../../src/common/PropaneConstants.sol";

/// @notice One test per rule family, with the slot-freeing exemptions of the
///         census rules exercised explicitly.
contract RulesTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");
    address internal c = makeAddr("c");
    address internal d = makeAddr("d");

    function _apply(PropaneComplianceEngine.Config memory cfg) internal {
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.warp(block.timestamp + engine.CONFIG_DELAY());
        engine.applyConfig();
    }

    function _base() internal view returns (PropaneComplianceEngine.Config memory cfg) {
        cfg = engine.config();
    }

    // ----------------------------------------------------------- config delay

    function test_configChangeIsDelayed() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.totalInvestorsLimit = 1;
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.expectRevert("Not ready");
        engine.applyConfig();
        assertEq(engine.config().limits.totalInvestorsLimit, 0);
    }

    function test_onlyIssuerSchedulesConfig() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        vm.prank(ta);
        vm.expectRevert();
        engine.scheduleConfig(cfg);
    }

    // ----------------------------------------------------------- investor-count caps

    function test_totalCap_blocksNewHolder_butExitFreesSlot() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.totalInvestorsLimit = 2;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        _register(c, OTHER, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(a, c, 10), 0, "partial transfer to a third holder exceeds the cap");
        assertEq(_code(a), PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        assertEq(_transfer(a, c, 100), 100, "full exit frees the slot");
        _assertCensus();
        assertEq(_counters()[0], 2);
    }

    function test_totalCap_atIssuance() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.totalInvestorsLimit = 1;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        assertEq(_issue(a, 10), 10);
        assertEq(_issue(b, 10), 0, "second holder refused at issuance");
        assertEq(_issue(a, 10), 10, "existing holder may receive more");
        _assertCensus();
    }

    function test_usPercentageCap_comparesTwoHiddenCounters() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.maxUSInvestorsPercentage = 50;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(b, OTHER, 0, false, false);
        _register(c, US, 0, true, false);
        _issue(a, 100);
        _issue(b, 100);
        // total 2, US 1, limit = 2 * 50 / 100 = 1: a new US holder from a non-US sender is refused.
        assertEq(_transfer(b, c, 10), 0);
        assertEq(_code(b), PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        // A US sender leaving entirely frees the slot.
        assertEq(_transfer(a, c, 100), 100);
        _assertCensus();
    }

    function test_usPercentageCap_zeroComputedLimitMeansNoCap() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.maxUSInvestorsPercentage = 10;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(c, US, 0, true, false);
        // total 0 then 1: floor(total * 10 / 100) = 0, so the prior art applies no cap.
        assertEq(_issue(a, 100), 100);
        assertEq(_transfer(a, c, 10), 10);
        _assertCensus();
    }

    function test_usAccreditedCap() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.usAccreditedInvestorsLimit = 1;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(b, OTHER, 0, false, false);
        _register(c, US, 0, true, false);
        _register(d, US, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(b, c, 10), 0, "second US accredited holder refused");
        assertEq(_code(b), PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        assertEq(_transfer(b, d, 10), 10, "US non-accredited holder not affected by this cap");
        _assertCensus();
    }

    function test_nonAccreditedCap() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.nonAccreditedInvestorsLimit = 1;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, true, false);
        _register(c, OTHER, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(b, c, 10), 0, "second non-accredited holder refused");
        assertEq(_transfer(a, c, 100), 100, "non-accredited exit frees the slot");
        _assertCensus();
    }

    function test_jpCap() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.jpInvestorsLimit = 1;
        _apply(cfg);
        _register(a, JP, 0, false, false);
        _register(b, OTHER, 0, false, false);
        _register(c, JP, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(b, c, 10), 0);
        assertEq(_code(b), PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        assertEq(_transfer(a, c, 100), 100, "JP holder leaving entirely frees the JP slot");
        _assertCensus();
    }

    function test_euRetailCap_isPerCountry_andIgnoresQualified() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.euRetailInvestorsLimit = 1;
        cfg.limits.euCountrySlots = 2;
        _apply(cfg);
        _register(a, EU, 0, false, false); // retail, country 0
        _register(b, OTHER, 0, false, false);
        _register(c, EU, 0, false, false); // retail, country 0
        _register(d, EU, 1, false, false); // retail, country 1
        address q = makeAddr("qualified");
        _register(q, EU, 0, false, true); // qualified, not retail
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(b, c, 10), 0, "country 0 retail slot full");
        assertEq(_transfer(b, d, 10), 10, "country 1 has its own slot");
        assertEq(_transfer(b, q, 10), 10, "qualified investors are not retail");
        _assertCensus();
        assertEq(_counters()[5], 1);
        assertEq(_counters()[6], 1);
    }

    function test_minimumTotalInvestors() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.limits.minimumTotalInvestors = 2;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(a, b, 100), 0, "full exit into an existing holder would drop below minimum");
        assertEq(_code(a), PropaneCodes.CODE_NOT_ENOUGH_INVESTORS);
        assertEq(_transfer(a, b, 50), 50, "partial transfer keeps the count");
    }

    // ----------------------------------------------------------- eligibility

    function test_forceAccredited() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.flags.forceAccredited = true;
        _apply(cfg);
        _register(a, OTHER, 0, true, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        assertEq(_transfer(a, b, 10), 0);
        assertEq(_code(a), PropaneCodes.CODE_ONLY_ACCREDITED);
    }

    function test_forceAccreditedUS() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.flags.forceAccreditedUS = true;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(b, US, 0, false, false);
        _register(c, OTHER, 0, false, false);
        _issue(a, 100);
        assertEq(_transfer(a, b, 10), 0);
        assertEq(_code(a), PropaneCodes.CODE_ONLY_US_ACCREDITED);
        assertEq(_transfer(a, c, 10), 10);
    }

    // ----------------------------------------------------------- holding bounds

    function test_holdingBounds() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.holdings.minimumHoldingsPerInvestor = 10;
        cfg.holdings.maximumHoldingsPerInvestor = 150;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        _issue(b, 100);
        assertEq(_transfer(a, b, 95), 0, "sender left under minimum");
        assertEq(_code(a), PropaneCodes.CODE_UNDER_MIN);
        assertEq(_transfer(a, b, 60), 0, "recipient at or above maximum");
        assertEq(_code(a), PropaneCodes.CODE_ABOVE_MAX);
        assertEq(_transfer(a, b, 40), 40);
    }

    function test_regionalMinimum_US() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.holdings.minUSTokens = 20;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(b, US, 0, true, false);
        _issue(a, 100);
        assertEq(_transfer(a, b, 10), 0, "US recipient under US minimum");
        assertEq(_code(a), PropaneCodes.CODE_UNDER_MIN);
        assertEq(_transfer(a, b, 90), 0, "US sender left under US minimum");
        assertEq(_transfer(a, b, 50), 50);
    }

    function test_forceFullTransferUS() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.flags.forceFullTransfer = true;
        _apply(cfg);
        _register(a, US, 0, true, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        assertEq(_transfer(a, b, 10), 0);
        assertEq(_code(a), PropaneCodes.CODE_ONLY_FULL_TRANSFER);
        assertEq(_transfer(a, b, 100), 100);
    }

    // ----------------------------------------------------------- lock-up and hold-up

    function test_holdUp_regionDependentLock() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.periods.usLockPeriod = 365 days;
        cfg.periods.nonUSLockPeriod = 40 days;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(u(), US, 0, true, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        _issue(u(), 100);
        assertEq(_transfer(a, b, 10), 0);
        assertEq(_code(a), PropaneCodes.CODE_HOLD_UP);
        assertEq(_transfer(u(), b, 10), 0);
        assertEq(_code(u()), PropaneCodes.CODE_HOLD_UP_US);
        vm.warp(block.timestamp + 41 days);
        assertEq(_transfer(a, b, 10), 10, "non-US lock expired");
        assertEq(_transfer(u(), b, 10), 0, "US lock still running");
        vm.warp(block.timestamp + 365 days);
        assertEq(_transfer(u(), b, 10), 10);
    }

    function test_holdUp_onlyLockedPortion() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.periods.nonUSLockPeriod = 30 days;
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, OTHER, 0, false, false);
        _issue(a, 100);
        vm.warp(block.timestamp + 31 days);
        _issue(a, 50); // locked
        assertEq(_transfer(a, b, 120), 0);
        assertEq(_transfer(a, b, 100), 100);
    }

    function test_flowback_unsetEndTimeBlocksIndefinitely() public {
        PropaneComplianceEngine.Config memory cfg = _base();
        cfg.periods.blockFlowbackEndTime = 0; // prior-art semantics
        _apply(cfg);
        _register(a, OTHER, 0, false, false);
        _register(b, US, 0, true, false);
        _issue(a, 100);
        assertEq(_transfer(a, b, 10), 0);
        assertEq(_code(a), PropaneCodes.CODE_FLOWBACK);
    }

    function u() internal returns (address) {
        return makeAddr("usHolder");
    }
}
