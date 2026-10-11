// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PropaneFixture} from "../system/PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/orbex/propaneEngine.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorBlacklistHead} from "../../src/compliance/dependency/heads/propaneInvestorBlacklistHead.sol";
import {PropaneInvestorTempBarredHead} from "../../src/compliance/dependency/heads/propaneInvestorTempBarredHead.sol";
import {PropaneInvestorWhitelistHead} from "../../src/compliance/dependency/heads/propaneInvestorWhitelistHead.sol";
import {PropaneInvestorEOAHead} from "../../src/compliance/dependency/heads/propaneInvestorEOAHead.sol";
import {externalEbool, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/// @notice The worst-case workload under the host contract's unmodified HCU limits (20M per
///         transaction, 5M sequential depth, 20M per block). Any limit breach reverts the test.
contract HcuFitTest is PropaneFixture {
    address internal a = makeAddr("a");
    address internal b = makeAddr("b");
    address internal c = makeAddr("c");

    function _config() internal view override returns (PropaneComplianceEngine.Config memory cfg) {
        cfg = super._config();
        cfg.limits.totalInvestorsLimit = 1000;
        cfg.limits.minimumTotalInvestors = 1;
        cfg.limits.usInvestorsLimit = 500;
        cfg.limits.maxUSInvestorsPercentage = 50;
        cfg.limits.usAccreditedInvestorsLimit = 400;
        cfg.limits.nonAccreditedInvestorsLimit = 400;
        cfg.limits.jpInvestorsLimit = 100;
        cfg.limits.euRetailInvestorsLimit = 100;
        cfg.limits.euCountrySlots = 4;
        cfg.holdings.minUSTokens = 1;
        cfg.holdings.minEUTokens = 1;
        cfg.holdings.minimumHoldingsPerInvestor = 1;
        cfg.holdings.maximumHoldingsPerInvestor = 1e12;
        cfg.flags.forceAccreditedUS = true;
        cfg.periods.usLockPeriod = 365 days;
        cfg.periods.nonUSLockPeriod = 40 days;
    }

    function test_worstCaseFitsRealLimits() public {
        address[4] memory impls = [
            address(new PropaneInvestorBlacklistHead()),
            address(new PropaneInvestorTempBarredHead()),
            address(new PropaneInvestorWhitelistHead()),
            address(new PropaneInvestorEOAHead())
        ];
        uint256[4] memory ids = [
            PropaneServices.SVC_BLACKLISTING_HEAD,
            PropaneServices.SVC_BARRING_HEAD,
            PropaneServices.SVC_WHITELISTING_HEAD,
            PropaneServices.SVC_EOA_HEAD
        ];
        address wl;
        for (uint256 i = 0; i < 4; i++) {
            address p = _proxy(impls[i], abi.encodeWithSignature("initialize(address)", address(loc)));
            loc.setInstitutionalService(ids[i], p);
            if (i == 2) wl = p;
        }
        _register(a, US, 0, true, false);
        _register(b, EU, 1, false, false);
        _register(c, JP, 0, false, false);
        (externalEbool h, bytes memory p2) = encryptBool(true, issuer, wl);
        _nextBlock();
        vm.prank(issuer);
        PropaneInvestorWhitelistHead(wl).setAdmitted(b, h, p2);

        _issue(a, 1000); // records a lock
        _issue(a, 10); // second open lock record
        vm.warp(block.timestamp + 400 days);
        assertEq(_transfer(a, b, 10), 10, "full ladder, four heads, two lock records");
        _assertCensus();

        _update(b, EU, 2, false, false);
        (externalEuint64 x, bytes memory px) = encryptUint64(5, a, address(engine));
        _nextBlock();
        vm.prank(a);
        engine.requestTransferCheck(a, b, x, px);

        _nextBlock();
        vm.prank(ta);
        census.beginRecompute();
        _nextBlock();
        census.continueRecompute(4); // four wallets per transaction
        _nextBlock();
        vm.prank(ta);
        census.finishRecompute();
        _assertCensus();
    }
}
