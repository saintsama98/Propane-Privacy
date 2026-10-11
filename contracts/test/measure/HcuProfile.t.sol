// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {PropaneFixture} from "../system/PropaneFixture.sol";
import {PropaneComplianceEngine} from "../../src/compliance/orbex/propaneEngine.sol";
import {IHCULimit} from "forge-fhevm/generated/interfaces/IHCULimit.sol";
import {hcuLimitAdd} from "forge-fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {PropaneServices} from "../../src/common/PropaneConstants.sol";
import {PropaneInvestorBlacklistHead} from "../../src/compliance/dependency/heads/propaneInvestorBlacklistHead.sol";
import {PropaneInvestorTempBarredHead} from "../../src/compliance/dependency/heads/propaneInvestorTempBarredHead.sol";
import {PropaneInvestorWhitelistHead} from "../../src/compliance/dependency/heads/propaneInvestorWhitelistHead.sol";
import {PropaneInvestorEOAHead} from "../../src/compliance/dependency/heads/propaneInvestorEOAHead.sol";

/// @notice HCU measurement. Records the HCU consumed by each operation under several rulebook
///         profiles, against the host contract's per-transaction and per-block limits. Limits are
///         raised for measurement only; the verdict on fit is made against the original limits.
contract HcuProfileTest is PropaneFixture {
    IHCULimit internal hcu = IHCULimit(hcuLimitAdd);
    uint48 internal maxTx;
    uint48 internal maxDepth;
    uint48 internal perBlock;

    address internal a = makeAddr("a");
    address internal b = makeAddr("b");
    address internal c = makeAddr("c");

    function setUp() public override {
        super.setUp();
        maxTx = hcu.getMaxHCUPerTx();
        maxDepth = hcu.getMaxHCUDepthPerTx();
        perBlock = hcu.getGlobalHCUCapPerBlock();
        address owner = _aclOwner();
        vm.startPrank(owner);
        hcu.setHCUPerBlock(type(uint48).max);
        hcu.setMaxHCUPerTx(type(uint48).max / 2);
        hcu.setMaxHCUDepthPerTx(type(uint48).max / 4);
        vm.stopPrank();
    }

    function _aclOwner() internal view returns (address o) {
        (bool ok, bytes memory r) = address(_acl).staticcall(abi.encodeWithSignature("owner()"));
        require(ok, "acl owner");
        o = abi.decode(r, (address));
    }

    function _used() internal view returns (uint256) {
        (, uint48 used) = hcu.getBlockMeter();
        return used;
    }

    function _apply(PropaneComplianceEngine.Config memory cfg) internal {
        vm.prank(issuer);
        engine.scheduleConfig(cfg);
        vm.warp(block.timestamp + engine.CONFIG_DELAY());
        engine.applyConfig();
    }

    function _report(string memory label, uint256 used) internal view {
        console2.log(
            string.concat(
                label,
                " HCU=",
                vm.toString(used),
                " fitsTx=",
                used <= maxTx ? "yes" : "NO",
                " perBlockCapacity=",
                vm.toString(used == 0 ? 0 : uint256(perBlock) / used)
            )
        );
    }

    function _measureTransfer(string memory label) internal {
        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(10, a, address(token));
        vm.prank(a);
        token.confidentialTransfer(b, h, p);
        _report(label, _used());
    }

    function _setup3() internal {
        _register(a, US, 0, true, false);
        _register(b, EU, 1, false, false);
        _register(c, JP, 0, false, false);
        _issue(a, 1000);
        _issue(c, 1000);
    }

    function test_profile() public {
        console2.log(
            string.concat(
                "limits maxHCUPerTx=",
                vm.toString(maxTx),
                " maxDepthPerTx=",
                vm.toString(maxDepth),
                " perBlock=",
                vm.toString(perBlock)
            )
        );

        _setup3();
        _measureTransfer("transfer.minimal");

        PropaneComplianceEngine.Config memory cfg = engine.config();
        cfg.limits.totalInvestorsLimit = 1000;
        cfg.limits.minimumTotalInvestors = 1;
        cfg.limits.usInvestorsLimit = 500;
        cfg.limits.maxUSInvestorsPercentage = 50;
        cfg.limits.usAccreditedInvestorsLimit = 400;
        cfg.limits.nonAccreditedInvestorsLimit = 400;
        cfg.limits.jpInvestorsLimit = 100;
        cfg.limits.euRetailInvestorsLimit = 100;
        cfg.limits.euCountrySlots = 4;
        _apply(cfg);
        _measureTransfer("transfer.census-rules");

        cfg.holdings.minUSTokens = 1;
        cfg.holdings.minEUTokens = 1;
        cfg.holdings.minimumHoldingsPerInvestor = 1;
        cfg.holdings.maximumHoldingsPerInvestor = 1e12;
        cfg.flags.forceAccreditedUS = true;
        _apply(cfg);
        _measureTransfer("transfer.census+holdings");

        cfg.periods.usLockPeriod = 365 days;
        cfg.periods.nonUSLockPeriod = 40 days;
        _apply(cfg);
        _nextBlock();
        _issue(a, 10);
        _report("issue.full", _used());
        _measureTransfer("transfer.full-rulebook+1lock");

        _nextBlock();
        _update(b, EU, 2, false, false);
        _report("attributeUpdate.holder", _used());

        _nextBlock();
        (externalEuint64 h, bytes memory p) = encryptUint64(10, a, address(engine));
        vm.prank(a);
        engine.requestTransferCheck(a, b, h, p);
        _report("precheck.full", _used());

        _wireHeads();
        _measureTransfer("transfer.full-rulebook+4heads");

        _nextBlock();
        vm.prank(ta);
        census.beginRecompute();
        _nextBlock();
        census.continueRecompute(1);
        _report("recompute.perWallet", _used());
    }

    function _wireHeads() internal {
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
        for (uint256 i = 0; i < 4; i++) {
            address p = _proxy(impls[i], abi.encodeWithSignature("initialize(address)", address(loc)));
            loc.setInstitutionalService(ids[i], p);
        }
    }
}
