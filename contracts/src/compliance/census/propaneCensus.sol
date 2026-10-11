//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, euint8, euint32, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices, PropaneRegions} from "../../common/PropaneConstants.sol";
import {
    IPropaneCensus,
    IPropaneCompliance,
    IPropaneRegistry,
    PropaneAttributes,
    PropaneCapInput,
    PropaneCensusLimits
} from "../../interfaces/IPropaneServices.sol";
import {IPropaneSecurityToken} from "../../security/IPropaneSecurityToken.sol";

/// @notice Enumeration surface of the registry, used only by census recomputation.
interface IPropaneRegistryEnumerable {
    function walletCount() external view returns (uint256);
    function walletAt(uint256 index) external view returns (address);
}

/*census head | the confidential investor census and its maintenance (Note 04, classes D and F)*/
/// @title PropaneCensus
/// @author Propane
/// @notice Holds the investor census as encrypted counters: total, accredited, US, US accredited,
///         JP, and EU retail per configured country slot. No counter is ever decrypted publicly
///         (Note 05, R1). Every move rewrites every counter with a possibly-zero delta (R2).
/// @dev Separated from the engine for two reasons: the census is the novel component and is easier
///      to verify in isolation, and the engine alone stays within the EIP-170 size limit.
contract PropaneCensus is PropaneServiceConsumer, IPropaneCensus {
    uint8 public constant CENSUS_EU_SLOTS = 4;

    /// @custom:storage-location erc7201:propane.storage.Census
    struct CensusStorage {
        Counters live;
        Counters shadow;
        uint256 recomputeCursor;
        bool recomputing;
    }

    // erc7201("propane.storage.Census")
    bytes32 private constant CENSUS_STORAGE = 0x7c3505e6d0c240fa3c9ba85f72d52b456f2731835a324b2edb5dece67e5fbd00;

    struct Cat {
        ebool acc;
        ebool us;
        ebool usAcc;
        ebool jp;
        ebool[4] eu;
    }

    event PropaneCensusRecomputeStarted();
    event PropaneCensusRecomputed();

    function _c() private pure returns (CensusStorage storage $) {
        bytes32 s = CENSUS_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
        _zero(_c().live);
    }

    /// @notice Handles of the counters. Decryptable only by the compliance service and the record keeper.
    function counters() external view returns (Counters memory) {
        return _c().live;
    }

    /// @notice Applies +1 to every category of `enterAttrs` when `enter` and -1 to every category of
    ///         `leaveAttrs` when `leave`. Callable by the compliance service only.
    function applyMove(
        PropaneAttributes calldata leaveAttrs,
        PropaneAttributes calldata enterAttrs,
        ebool leave,
        ebool enter
    ) external onlyService(PropaneServices.SVC_COMPLIANCE) {
        _apply(_c().live, leaveAttrs, enterAttrs, leave, enter);
        _persist(_c().live);
    }

    /// @notice Class D rules. Each cap is checked only for a recipient that would become a new holder,
    ///         and is waived where the sender leaves the same category in the same transfer
    ///         (Note 04, section 3.4). Issuance is evaluated with a synthetic sender that frees nothing.
    function capChecks(PropaneCapInput calldata i)
        external
        onlyService(PropaneServices.SVC_COMPLIANCE)
        returns (ebool regional, ebool global, ebool tooFew)
    {
        PropaneCensusLimits memory lim = IPropaneCompliance(msg.sender).censusLimits();
        Counters storage cen = _c().live;
        regional = _regionalCaps(i, lim, cen);
        global = FHE.asEbool(false);
        tooFew = FHE.asEbool(false);
        if (lim.nonAccreditedInvestorsLimit != 0) {
            ebool atCap = FHE.ge(FHE.sub(cen.total, cen.accredited), lim.nonAccreditedInvestorsLimit);
            ebool notExempt = FHE.or(i.fromAccredited, i.fromPartial);
            global = FHE.or(global, FHE.and(FHE.not(i.toAccredited), FHE.and(atCap, FHE.and(i.toNew, notExempt))));
        }
        if (lim.totalInvestorsLimit != 0) {
            global =
                FHE.or(global, FHE.and(i.fromPartial, FHE.and(FHE.ge(cen.total, lim.totalInvestorsLimit), i.toNew)));
        }
        if (lim.minimumTotalInvestors != 0) {
            tooFew = FHE.and(i.fromFull, FHE.and(FHE.not(i.toNew), FHE.le(cen.total, lim.minimumTotalInvestors)));
        }
        FHE.allowTransient(regional, msg.sender);
        FHE.allowTransient(global, msg.sender);
        FHE.allowTransient(tooFew, msg.sender);
    }

    function _regionalCaps(PropaneCapInput calldata i, PropaneCensusLimits memory lim, Counters storage cen)
        private
        returns (ebool f)
    {
        f = FHE.asEbool(false);
        if (lim.jpInvestorsLimit != 0) {
            ebool frees = FHE.or(FHE.ne(i.fromRegion, PropaneRegions.REGION_JP), i.fromPartial);
            f = FHE.or(f, FHE.and(i.toJP, FHE.and(FHE.ge(cen.jp, lim.jpInvestorsLimit), FHE.and(i.toNew, frees))));
        }
        if (lim.euRetailInvestorsLimit != 0 && lim.euCountrySlots != 0) {
            f = FHE.or(f, _euRetailCap(i, lim, cen));
        }
        if (lim.usInvestorsLimit != 0 || lim.maxUSInvestorsPercentage != 0) {
            ebool notExempt = FHE.or(FHE.not(i.fromUS), i.fromPartial);
            f = FHE.or(f, FHE.and(i.toUS, FHE.and(notExempt, FHE.and(_usAtCap(cen, lim, i.isIssuance), i.toNew))));
        }
        if (lim.usAccreditedInvestorsLimit != 0) {
            ebool notExempt = FHE.or(FHE.not(i.fromUS), FHE.or(FHE.not(i.fromAccredited), i.fromPartial));
            ebool atCap = FHE.ge(cen.usAccredited, lim.usAccreditedInvestorsLimit);
            f = FHE.or(f, FHE.and(FHE.and(i.toUS, i.toAccredited), FHE.and(FHE.and(i.toNew, atCap), notExempt)));
        }
    }

    function _euRetailCap(PropaneCapInput calldata i, PropaneCensusLimits memory lim, Counters storage cen)
        private
        returns (ebool)
    {
        euint32 count = FHE.asEuint32(0);
        for (uint8 k = 0; k < lim.euCountrySlots; k++) {
            count = FHE.add(count, FHE.select(FHE.eq(i.toEuCountry, k), cen.euRetail[k], FHE.asEuint32(0)));
        }
        ebool sameCountry = FHE.and(i.fromEU, FHE.eq(i.fromEuCountry, i.toEuCountry));
        ebool frees = FHE.or(FHE.not(sameCountry), FHE.and(i.fromPartial, FHE.not(i.fromQualified)));
        ebool atCap = FHE.ge(count, lim.euRetailInvestorsLimit);
        return FHE.and(FHE.and(i.toEU, FHE.not(i.toQualified)), FHE.and(atCap, FHE.and(i.toNew, frees)));
    }

    /// @dev The US limit is the absolute limit, a percentage of the total, or the smaller of the two.
    ///      As in the prior art, a computed limit of zero means no cap, and issuance applies the
    ///      absolute limit only. The percentage branch compares one hidden counter with a function of
    ///      another (Note 05, R4). Encrypted division exceeds the per-transaction HCU depth limit, so
    ///      floor division is replaced by exact identities over multiplication:
    ///        floor(total * pct / 100) != 0      <=>  total * pct >= 100
    ///        us >= floor(total * pct / 100)     <=>  100 * (us + 1) > total * pct
    ///        us >= min(abs, p)                  <=>  us >= abs  or  us >= p
    function _usAtCap(Counters storage cen, PropaneCensusLimits memory lim, bool issuance) private returns (ebool) {
        bool useAbs = lim.usInvestorsLimit != 0;
        bool usePct = lim.maxUSInvestorsPercentage != 0 && !issuance;
        if (!usePct) return useAbs ? FHE.ge(cen.us, lim.usInvestorsLimit) : FHE.asEbool(false);
        euint32 scaled = FHE.mul(cen.total, lim.maxUSInvestorsPercentage);
        ebool pctNonZero = FHE.ge(scaled, uint32(100));
        ebool atPct = FHE.gt(FHE.mul(FHE.add(cen.us, uint32(1)), uint32(100)), scaled);
        ebool reached = useAbs ? FHE.or(FHE.ge(cen.us, lim.usInvestorsLimit), atPct) : atPct;
        return FHE.and(pctNonZero, reached);
    }

    /// @notice Starts recomputing the census from chain state. Replaces the prior art's
    ///         administrative overwrite: the result derives from balances and attributes, so it needs
    ///         no trust in whoever triggers it (Note 05, R14).
    function beginRecompute() external onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER) {
        CensusStorage storage $ = _c();
        _zero($.shadow);
        $.recomputeCursor = 0;
        $.recomputing = true;
        emit PropaneCensusRecomputeStarted();
    }

    /// @notice Processes up to `count` registered wallets in registry order. Callable by anyone.
    function continueRecompute(uint256 count) external {
        CensusStorage storage $ = _c();
        require($.recomputing, "Not recomputing");
        IPropaneRegistryEnumerable reg = IPropaneRegistryEnumerable(_service(PropaneServices.SVC_REGISTRY));
        IPropaneSecurityToken token = IPropaneSecurityToken(_service(PropaneServices.SVC_TOKEN));
        IPropaneCompliance compliance = IPropaneCompliance(_service(PropaneServices.SVC_COMPLIANCE));
        uint256 n = reg.walletCount();
        uint256 end = $.recomputeCursor + count;
        if (end > n) end = n;
        for (uint256 i = $.recomputeCursor; i < end; i++) {
            address w = reg.walletAt(i);
            if (compliance.isPlatformWallet(w)) continue;
            euint64 bal = token.confidentialBalanceOf(w);
            if (!FHE.isInitialized(bal)) continue;
            PropaneAttributes memory a = IPropaneRegistry(address(reg)).attributes(w);
            _apply($.shadow, a, a, FHE.asEbool(false), FHE.ne(bal, uint64(0)));
        }
        $.recomputeCursor = end;
    }

    function finishRecompute() external onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER) {
        CensusStorage storage $ = _c();
        require($.recomputing, "Not recomputing");
        require(
            $.recomputeCursor == IPropaneRegistryEnumerable(_service(PropaneServices.SVC_REGISTRY)).walletCount(),
            "Recompute incomplete"
        );
        $.live = $.shadow;
        $.recomputing = false;
        _persist($.live);
        emit PropaneCensusRecomputed();
    }

    function _apply(
        Counters storage cen,
        PropaneAttributes memory leaveAttrs,
        PropaneAttributes memory enterAttrs,
        ebool leave,
        ebool enter
    ) private {
        uint8 slots = IPropaneCompliance(_service(PropaneServices.SVC_COMPLIANCE)).euCountrySlots();
        Cat memory out = _cat(leaveAttrs, slots);
        Cat memory inn = _cat(enterAttrs, slots);
        cen.total = _shift(cen.total, enter, leave);
        cen.accredited = _shift(cen.accredited, FHE.and(enter, inn.acc), FHE.and(leave, out.acc));
        cen.us = _shift(cen.us, FHE.and(enter, inn.us), FHE.and(leave, out.us));
        cen.usAccredited = _shift(cen.usAccredited, FHE.and(enter, inn.usAcc), FHE.and(leave, out.usAcc));
        cen.jp = _shift(cen.jp, FHE.and(enter, inn.jp), FHE.and(leave, out.jp));
        for (uint256 k = 0; k < slots; k++) {
            cen.euRetail[k] = _shift(cen.euRetail[k], FHE.and(enter, inn.eu[k]), FHE.and(leave, out.eu[k]));
        }
        _keepAll(cen, address(this), address(0));
    }

    function _cat(PropaneAttributes memory a, uint8 slots) private returns (Cat memory k) {
        ebool acc = FHE.isInitialized(a.accredited) ? a.accredited : FHE.asEbool(false);
        bool hasRegion = FHE.isInitialized(a.region);
        k.acc = acc;
        k.us = hasRegion ? FHE.eq(a.region, PropaneRegions.REGION_US) : FHE.asEbool(false);
        k.usAcc = FHE.and(k.us, acc);
        k.jp = hasRegion ? FHE.eq(a.region, PropaneRegions.REGION_JP) : FHE.asEbool(false);
        if (slots != 0 && hasRegion) {
            ebool qualified = FHE.isInitialized(a.qualified) ? a.qualified : FHE.asEbool(false);
            ebool euRetail = FHE.and(FHE.eq(a.region, PropaneRegions.REGION_EU), FHE.not(qualified));
            for (uint8 i = 0; i < slots; i++) {
                k.eu[i] = FHE.isInitialized(a.euCountry)
                    ? FHE.and(euRetail, FHE.eq(a.euCountry, i))
                    : (i == 0 ? euRetail : FHE.asEbool(false));
            }
        } else {
            for (uint8 i = 0; i < slots; i++) {
                k.eu[i] = FHE.asEbool(false);
            }
        }
    }

    function _shift(euint32 c, ebool inc, ebool dec) private returns (euint32) {
        return FHE.sub(FHE.add(c, FHE.asEuint32(inc)), FHE.asEuint32(dec));
    }

    function _zero(Counters storage c) private {
        euint32 z = FHE.asEuint32(0);
        c.total = z;
        c.accredited = z;
        c.us = z;
        c.usAccredited = z;
        c.jp = z;
        for (uint256 k = 0; k < CENSUS_EU_SLOTS; k++) {
            c.euRetail[k] = z;
        }
        FHE.allowThis(z);
    }

    /// @dev Grants the compliance service and the record keeper persistent access to the live counters.
    function _persist(Counters storage c) private {
        _keepAll(c, _serviceOrZero(PropaneServices.SVC_COMPLIANCE), _recordKeeper());
    }

    function _keepAll(Counters storage c, address a, address b) private {
        _keep(c.total, a, b);
        _keep(c.accredited, a, b);
        _keep(c.us, a, b);
        _keep(c.usAccredited, a, b);
        _keep(c.jp, a, b);
        for (uint256 k = 0; k < CENSUS_EU_SLOTS; k++) {
            _keep(c.euRetail[k], a, b);
        }
    }

    function _keep(euint32 v, address a, address b) private {
        FHE.allowThis(v);
        if (a != address(0) && a != address(this)) FHE.allow(v, a);
        if (b != address(0)) FHE.allow(v, b);
    }
}
