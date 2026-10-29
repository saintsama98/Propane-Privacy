//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {FHE, ebool, euint8, euint32, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices, PropaneRegions, PropaneCodes} from "../../common/PropaneConstants.sol";
import {
    IPropaneCensus,
    IPropaneCompliance,
    IPropaneLockHead,
    IPropaneRegistry,
    IPropaneRuleHead,
    PropaneAttributes,
    PropaneCapInput,
    PropaneCensusLimits
} from "../../interfaces/IPropaneServices.sol";
import {IPropaneSecurityToken} from "../../security/IPropaneSecurityToken.sol";

/*compliance engine | the prior-art rule ladder evaluated over encrypted state, with a confidential census*/
/// @title PropaneComplianceEngine
/// @author Propane
/// @notice Evaluates every rule of the regulated ladder (eligibility, holding bounds, lock-ups and
///         investor-count caps) over
///         encrypted balances, amounts and attributes, and maintains the investor census as encrypted
///         counters that are never decrypted publicly.
/// @dev Design properties:
///      - census counters are readable only by this contract and the record keeper.
///      - every transfer, issuance, burn, forced transfer and attribute change applies a delta,
///        possibly zero, to every counter, so the public cannot tell a holder change from none.
///      - census rules are evaluated jointly over both parties and the counters, including
///        counter-to-counter comparison for the percentage cap.
///      - a refusal is never a revert. The transfer moves zero, the reason code is
///        disclosed to the subject and the record keeper only, and the pre-check answers only the
///        subject, its delegate, or the transfer agent.
///      Rule order and reason codes follow the prior art so behaviour can be compared rule by rule.
contract PropaneComplianceEngine is PropaneServiceConsumer, IPropaneCompliance {
    uint8 public constant MAX_EU_SLOTS = 4;
    uint64 public constant CONFIG_DELAY = 1 days;

    struct Holdings {
        uint64 minUSTokens;
        uint64 minEUTokens;
        uint64 minimumHoldingsPerInvestor;
        uint64 maximumHoldingsPerInvestor;
    }

    struct Flags {
        bool forceAccredited;
        bool forceAccreditedUS;
        bool forceFullTransfer;
        bool worldWideForceFullTransfer;
    }

    struct Periods {
        uint64 usLockPeriod;
        uint64 nonUSLockPeriod;
        uint64 blockFlowbackEndTime;
    }

    /// @notice The rulebook. Public by design: it describes the offering, not any investor.
    struct Config {
        PropaneCensusLimits limits;
        Holdings holdings;
        Flags flags;
        Periods periods;
    }

    /// @custom:storage-location erc7201:propane.storage.ComplianceEngine
    struct EngineStorage {
        Config config;
        Config pending;
        uint64 pendingEta;
        mapping(address wallet => bool) platform;
        mapping(address wallet => euint8) lastCode;
        mapping(address investor => mapping(address venue => bool)) delegates;
    }

    // erc7201("propane.storage.ComplianceEngine")
    bytes32 private constant ENGINE_STORAGE = 0x7f6fe5caf44e81281ad4f4683519117715de18bc6f5cf1674394c6c723a88c00;

    /// @dev Evaluation context. Handles only; nothing here is in the clear except addresses and flags.
    struct Ctx {
        address from;
        address to;
        bool fromPlatform;
        bool toPlatform;
        euint64 amount;
        euint64 available;
        euint64 fromBal;
        euint64 toBal;
        PropaneAttributes fa;
        PropaneAttributes ta;
        ebool fromUS;
        ebool fromEU;
        ebool toUS;
        ebool toEU;
        ebool toJP;
        ebool toNew;
        ebool fromPartial;
        ebool fromFull;
    }

    struct Ladder {
        ebool[32] f;
        uint8[32] k;
        uint256 n;
    }

    event PropaneConfigScheduled(uint64 eta);
    event PropaneConfigApplied();
    event PropanePlatformWalletSet(address indexed wallet, bool isPlatform);
    event PropaneDelegateSet(address indexed investor, address indexed venue, bool allowed);
    event PropaneTransferEvaluated(address indexed from, address indexed to, euint8 code);
    event PropaneTransferChecked(
        address indexed caller, address indexed from, address indexed to, ebool verdict, euint8 code
    );

    function _s() private pure returns (EngineStorage storage $) {
        bytes32 s = ENGINE_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_, Config calldata config_) external initializer {
        __PropaneServiceConsumer_init(locator_);
        require(config_.limits.euCountrySlots <= MAX_EU_SLOTS, "Too many EU slots");
        _s().config = config_;
    }

    // ---------------------------------------------------------------------------------------------
    // Configuration (changes take effect after a delay, so a lowered cap is not a timed probe)
    // ---------------------------------------------------------------------------------------------

    function scheduleConfig(Config calldata next)
        external
        onlyRoles2(PropaneRoles.ROLE_OWNER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        EngineStorage storage $ = _s();
        require(next.limits.euCountrySlots <= MAX_EU_SLOTS, "Too many EU slots");
        // Shrinking the EU slot set would orphan holders counted in the dropped slots.
        require(next.limits.euCountrySlots >= $.config.limits.euCountrySlots, "EU slots cannot shrink");
        $.pending = next;
        $.pendingEta = uint64(block.timestamp) + CONFIG_DELAY;
        emit PropaneConfigScheduled($.pendingEta);
    }

    function applyConfig() external {
        EngineStorage storage $ = _s();
        require($.pendingEta != 0 && block.timestamp >= $.pendingEta, "Not ready");
        $.config = $.pending;
        $.pendingEta = 0;
        emit PropaneConfigApplied();
    }

    function config() external view returns (Config memory) {
        return _s().config;
    }

    /// @notice Platform wallets (venue omnibus and issuer treasury) bypass most rules and are
    ///         excluded from the census, as in the prior art. Platform status is public.
    /// @dev Must be set before the wallet holds anything; flipping a holding wallet leaves the census
    ///      off by that holder until the next recomputation.
    function setPlatformWallet(address wallet, bool isPlatform_)
        external
        onlyRoles2(PropaneRoles.ROLE_PROPANE, PropaneRoles.ROLE_SUPER_OWNER)
    {
        _s().platform[wallet] = isPlatform_;
        emit PropanePlatformWalletSet(wallet, isPlatform_);
    }

    function isPlatformWallet(address wallet) public view returns (bool) {
        return _s().platform[wallet];
    }

    function euCountrySlots() external view returns (uint8) {
        return _s().config.limits.euCountrySlots;
    }

    function censusLimits() external view returns (PropaneCensusLimits memory) {
        return _s().config.limits;
    }

    function lockPeriods() external view returns (uint64, uint64) {
        Periods storage p = _s().config.periods;
        return (p.usLockPeriod, p.nonUSLockPeriod);
    }

    /// @notice An investor authorises a venue to run pre-checks on its behalf.
    function setDelegate(address venue, bool allowed) external {
        _s().delegates[msg.sender][venue] = allowed;
        emit PropaneDelegateSet(msg.sender, venue, allowed);
    }

    function isDelegate(address investor, address venue) external view returns (bool) {
        return _s().delegates[investor][venue];
    }

    // ---------------------------------------------------------------------------------------------
    // Mutating paths (token and registry only)
    // ---------------------------------------------------------------------------------------------

    function validateTransfer(address from, address to, euint64 amount, euint64 available)
        external
        onlyService(PropaneServices.SVC_TOKEN)
        returns (euint64 effective)
    {
        Ctx memory c = _context(from, to, amount, available);
        (ebool fail, euint8 code) = _evaluate(c);
        effective = FHE.select(fail, FHE.asEuint64(0), amount);

        FHE.allowThis(code);
        FHE.allow(code, from);
        _toKeeper(code);
        _s().lastCode[from] = code;
        emit PropaneTransferEvaluated(from, to, code);

        _censusMove(c, effective);
        FHE.allowTransient(effective, msg.sender);
    }

    function validateIssuance(address to, euint64 amount)
        external
        onlyService(PropaneServices.SVC_TOKEN)
        returns (euint64 effective)
    {
        EngineStorage storage $ = _s();
        bool toPlatform = $.platform[to];
        PropaneAttributes memory ta = _attrs(to);
        euint64 toBal = _bal(to);
        ebool toNew = FHE.eq(toBal, uint64(0));

        ebool fail = toPlatform ? FHE.asEbool(false) : _issuanceFails(ta, toBal, toNew, amount);
        effective = FHE.select(fail, FHE.asEuint64(0), amount);

        if (!toPlatform) {
            ebool enter = FHE.and(toNew, FHE.ne(effective, uint64(0)));
            _move(ta, ta, FHE.asEbool(false), enter);
        }
        address lockHead = _serviceOrZero(PropaneServices.SVC_LOCK_HEAD);
        if (lockHead != address(0)) {
            FHE.allowTransient(effective, lockHead);
            IPropaneLockHead(lockHead).recordIssuance(to, effective);
        }
        FHE.allowTransient(effective, msg.sender);
    }

    function validateBurn(address from, euint64 amount, euint64 balance)
        external
        onlyService(PropaneServices.SVC_TOKEN)
        returns (euint64 effective)
    {
        effective = FHE.select(FHE.le(amount, balance), amount, FHE.asEuint64(0));
        if (!_s().platform[from]) {
            PropaneAttributes memory fa = _attrs(from);
            ebool leave = FHE.and(FHE.eq(balance, effective), FHE.ne(effective, uint64(0)));
            _move(fa, fa, leave, FHE.asEbool(false));
        }
        FHE.allowTransient(effective, msg.sender);
    }

    /// @notice Enforcement path (ERC-7943 forcedTransfer, and seizure into an issuer platform
    ///         wallet). Eligibility rules are bypassed by design; the census is not.
    function validateForcedTransfer(address from, address to, euint64 amount, euint64 balance)
        external
        onlyService(PropaneServices.SVC_TOKEN)
        returns (euint64 effective)
    {
        EngineStorage storage $ = _s();
        effective = FHE.select(FHE.le(amount, balance), amount, FHE.asEuint64(0));
        ebool nz = FHE.ne(effective, uint64(0));
        ebool leave = $.platform[from] ? FHE.asEbool(false) : FHE.and(FHE.eq(balance, effective), nz);
        ebool enter = $.platform[to] ? FHE.asEbool(false) : FHE.and(FHE.eq(_bal(to), uint64(0)), nz);
        _move(_attrs(from), _attrs(to), leave, enter);
        FHE.allowTransient(effective, msg.sender);
    }

    /// @notice Moves a holder between category counters when its attributes change. Applied to every
    ///         counter with a possibly-zero delta; the total counter is unchanged by construction.
    function onAttributesChanged(address wallet, PropaneAttributes calldata previous, PropaneAttributes calldata next)
        external
        onlyService(PropaneServices.SVC_REGISTRY)
    {
        if (_s().platform[wallet]) return;
        euint64 bal = IPropaneSecurityToken(_service(PropaneServices.SVC_TOKEN)).confidentialBalanceOf(wallet);
        // A wallet that has never held has an uninitialised balance handle: public, and a no-op.
        if (!FHE.isInitialized(bal)) return;
        ebool holder = FHE.ne(bal, uint64(0));
        _move(_initAttrs(previous), _initAttrs(next), holder, holder);
    }

    // ---------------------------------------------------------------------------------------------
    // Pre-check: caller-scoped, mutating only to store access grants
    // ---------------------------------------------------------------------------------------------

    /// @notice Establishes whether a transfer would succeed, without executing it. Answers only the
    ///         subject, a venue the subject has delegated to, or the transfer agent. The verdict is
    ///         granted to the caller; the reason code to the subject only.
    /// @dev Deviation from ERC-7943: `canTransfer` is a view returning a boolean. An encrypted
    ///      evaluation creates handles and grants access, so it cannot be a view.
    function requestTransferCheck(address from, address to, externalEuint64 amount, bytes calldata proof)
        external
        returns (ebool verdict, euint8 code)
    {
        if (msg.sender != from && !_s().delegates[from][msg.sender] && _roleOf(msg.sender) != PropaneRoles.ROLE_OFFICER)
        {
            revert PropaneUnauthorized(msg.sender);
        }

        euint64 amt = FHE.fromExternal(amount, proof);
        euint64 available = IPropaneSecurityToken(_service(PropaneServices.SVC_TOKEN)).computeAvailable(from);
        Ctx memory c = _context(from, to, amt, available);
        ebool fail;
        (fail, code) = _evaluate(c);
        verdict = FHE.not(fail);

        FHE.allowThis(verdict);
        FHE.allow(verdict, msg.sender);
        FHE.allowThis(code);
        FHE.allow(code, from);
        _toKeeper(code);
        emit PropaneTransferChecked(msg.sender, from, to, verdict, code);
    }

    function lastCode(address wallet) external view returns (euint8) {
        return _s().lastCode[wallet];
    }

    // ---------------------------------------------------------------------------------------------
    // Evaluation
    // ---------------------------------------------------------------------------------------------

    function _context(address from, address to, euint64 amount, euint64 available) private returns (Ctx memory c) {
        EngineStorage storage $ = _s();
        c.from = from;
        c.to = to;
        c.fromPlatform = $.platform[from];
        c.toPlatform = $.platform[to];
        c.amount = amount;
        c.available = available;
        c.fromBal = _bal(from);
        c.toBal = _bal(to);
        c.fa = _attrs(from);
        c.ta = _attrs(to);
        c.fromUS = FHE.eq(c.fa.region, PropaneRegions.REGION_US);
        c.fromEU = FHE.eq(c.fa.region, PropaneRegions.REGION_EU);
        c.toUS = FHE.eq(c.ta.region, PropaneRegions.REGION_US);
        c.toEU = FHE.eq(c.ta.region, PropaneRegions.REGION_EU);
        c.toJP = FHE.eq(c.ta.region, PropaneRegions.REGION_JP);
        c.toNew = FHE.eq(c.toBal, uint64(0));
        c.fromPartial = FHE.gt(c.fromBal, amount);
        c.fromFull = FHE.eq(c.fromBal, amount);
    }

    /// @dev Builds the ladder in prior-art order and folds it so that the earliest failing rule
    ///      supplies the code. Rules whose configuration disables them are skipped; that decision
    ///      depends only on public configuration and so reveals nothing.
    function _evaluate(Ctx memory c) private returns (ebool fail, euint8 code) {
        Config storage cfg = _s().config;
        Ladder memory l;

        _push(l, FHE.lt(c.available, c.amount), PropaneCodes.CODE_NOT_ENOUGH_TOKENS);

        // Same investor on both sides: valid once funded, as in the prior art. Public, since both
        // addresses are public.
        if (c.from == c.to) return _fold(l);

        if (c.toPlatform) {
            if (cfg.flags.forceFullTransfer || cfg.flags.worldWideForceFullTransfer) {
                ebool full = cfg.flags.worldWideForceFullTransfer ? FHE.asEbool(true) : c.fromUS;
                _push(l, FHE.and(full, c.fromPartial), PropaneCodes.CODE_ONLY_FULL_TRANSFER);
            }
            return _fold(l);
        }

        _pushHeads(l, c.from, c.to);
        _push(l, c.ta.liquidateOnly, PropaneCodes.CODE_LIQUIDATE_ONLY);
        if (!IPropaneRegistry(_service(PropaneServices.SVC_REGISTRY)).isRegistered(c.to)) {
            _push(l, FHE.asEbool(true), PropaneCodes.CODE_NOT_REGISTERED);
        }
        _push(l, FHE.eq(c.ta.region, PropaneRegions.REGION_FORBIDDEN), PropaneCodes.CODE_DESTINATION_RESTRICTED);
        _pushHoldUp(l, c, cfg);
        _pushSenderRules(l, c, cfg);
        _pushRecipientRules(l, c, cfg);
        _pushCensusRules(l, c, cfg);
        _pushHoldingRules(l, c, cfg);
        return _fold(l);
    }

    function _pushHeads(Ladder memory l, address from, address to) private {
        uint256[4] memory ids = [
            PropaneServices.SVC_BLACKLISTING_HEAD,
            PropaneServices.SVC_BARRING_HEAD,
            PropaneServices.SVC_WHITELISTING_HEAD,
            PropaneServices.SVC_EOA_HEAD
        ];
        for (uint256 i = 0; i < ids.length; i++) {
            address head = _serviceOrZero(ids[i]);
            if (head != address(0)) {
                _push(l, IPropaneRuleHead(head).blocked(from, to), PropaneCodes.CODE_HEAD_BLOCKED);
            }
        }
    }

    /// @dev Lock-up and hold-up rules, evaluated by the lock head (the prior art's lock manager).
    function _pushHoldUp(Ladder memory l, Ctx memory c, Config storage) private {
        if (c.fromPlatform) return;
        address lockHead = _serviceOrZero(PropaneServices.SVC_LOCK_HEAD);
        if (lockHead == address(0)) return;
        FHE.allowTransient(c.fromUS, lockHead);
        FHE.allowTransient(c.available, lockHead);
        FHE.allowTransient(c.amount, lockHead);
        ebool f = IPropaneLockHead(lockHead).lockedFails(c.from, c.fromUS, c.available, c.amount);
        _push(l, FHE.and(f, c.fromUS), PropaneCodes.CODE_HOLD_UP_US);
        _push(l, FHE.and(f, FHE.not(c.fromUS)), PropaneCodes.CODE_HOLD_UP);
    }

    function _pushSenderRules(Ladder memory l, Ctx memory c, Config storage cfg) private {
        euint64 remaining = FHE.sub(c.fromBal, c.amount); // meaningful only where fromPartial holds
        if (cfg.holdings.minUSTokens != 0) {
            _push(
                l,
                FHE.and(c.fromUS, FHE.and(c.fromPartial, FHE.lt(remaining, cfg.holdings.minUSTokens))),
                PropaneCodes.CODE_UNDER_MIN
            );
        }
        if (cfg.flags.forceFullTransfer) {
            _push(l, FHE.and(c.fromUS, c.fromPartial), PropaneCodes.CODE_ONLY_FULL_TRANSFER);
        }
        uint64 fbEnd = cfg.periods.blockFlowbackEndTime;
        // Prior art: an unset end time blocks flowback indefinitely.
        if (!c.fromPlatform && (fbEnd == 0 || fbEnd > block.timestamp)) {
            _push(l, FHE.and(FHE.not(c.fromUS), c.toUS), PropaneCodes.CODE_FLOWBACK);
        }
        if (cfg.flags.worldWideForceFullTransfer) {
            _push(l, FHE.and(FHE.not(c.fromUS), c.fromPartial), PropaneCodes.CODE_ONLY_FULL_TRANSFER);
        }
        if (cfg.holdings.minEUTokens != 0) {
            _push(
                l,
                FHE.and(c.fromEU, FHE.and(c.fromPartial, FHE.lt(remaining, cfg.holdings.minEUTokens))),
                PropaneCodes.CODE_UNDER_MIN
            );
        }
    }

    function _pushRecipientRules(Ladder memory l, Ctx memory c, Config storage cfg) private {
        if (cfg.flags.forceAccredited) {
            _push(l, FHE.not(c.ta.accredited), PropaneCodes.CODE_ONLY_ACCREDITED);
        }
        if (cfg.flags.forceAccreditedUS) {
            _push(l, FHE.and(c.toUS, FHE.not(c.ta.accredited)), PropaneCodes.CODE_ONLY_US_ACCREDITED);
        }
    }

    /// @dev Investor-count cap rules, evaluated by the census service against its counters, interleaved with the
    ///      regional minimums in prior-art order: regional caps, regional minimums, global caps,
    ///      minimum investors.
    function _pushCensusRules(Ladder memory l, Ctx memory c, Config storage cfg) private {
        PropaneCapInput memory i = PropaneCapInput({
            fromUS: c.fromUS,
            fromEU: c.fromEU,
            fromAccredited: c.fa.accredited,
            fromQualified: c.fa.qualified,
            fromPartial: c.fromPartial,
            fromFull: c.fromFull,
            fromRegion: c.fa.region,
            fromEuCountry: c.fa.euCountry,
            toUS: c.toUS,
            toEU: c.toEU,
            toJP: c.toJP,
            toAccredited: c.ta.accredited,
            toQualified: c.ta.qualified,
            toNew: c.toNew,
            toEuCountry: c.ta.euCountry,
            isIssuance: false
        });
        (ebool regional, ebool global, ebool tooFew) = _capChecks(i);
        _push(l, regional, PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        euint64 toAfter = FHE.add(c.toBal, c.amount);
        if (cfg.holdings.minEUTokens != 0) {
            _push(l, FHE.and(c.toEU, FHE.lt(toAfter, cfg.holdings.minEUTokens)), PropaneCodes.CODE_UNDER_MIN);
        }
        if (cfg.holdings.minUSTokens != 0) {
            _push(l, FHE.and(c.toUS, FHE.lt(toAfter, cfg.holdings.minUSTokens)), PropaneCodes.CODE_UNDER_MIN);
        }
        _push(l, global, PropaneCodes.CODE_MAX_INVESTORS_IN_CATEGORY);
        _push(l, tooFew, PropaneCodes.CODE_NOT_ENOUGH_INVESTORS);
    }

    function _capChecks(PropaneCapInput memory i) private returns (ebool, ebool, ebool) {
        address census = _service(PropaneServices.SVC_CENSUS);
        FHE.allowTransient(i.fromUS, census);
        FHE.allowTransient(i.fromEU, census);
        FHE.allowTransient(i.fromAccredited, census);
        FHE.allowTransient(i.fromQualified, census);
        FHE.allowTransient(i.fromPartial, census);
        FHE.allowTransient(i.fromFull, census);
        FHE.allowTransient(i.fromRegion, census);
        FHE.allowTransient(i.fromEuCountry, census);
        FHE.allowTransient(i.toUS, census);
        FHE.allowTransient(i.toEU, census);
        FHE.allowTransient(i.toJP, census);
        FHE.allowTransient(i.toAccredited, census);
        FHE.allowTransient(i.toQualified, census);
        FHE.allowTransient(i.toNew, census);
        FHE.allowTransient(i.toEuCountry, census);
        return IPropaneCensus(census).capChecks(i);
    }

    function _pushHoldingRules(Ladder memory l, Ctx memory c, Config storage cfg) private {
        euint64 toAfter = FHE.add(c.toBal, c.amount);
        uint64 minHold = cfg.holdings.minimumHoldingsPerInvestor;
        if (minHold != 0) {
            if (!c.fromPlatform) {
                ebool f = FHE.and(c.fromPartial, FHE.lt(FHE.sub(c.fromBal, c.amount), minHold));
                _push(l, f, PropaneCodes.CODE_UNDER_MIN);
            }
            _push(l, FHE.lt(toAfter, minHold), PropaneCodes.CODE_UNDER_MIN);
        }
        if (cfg.holdings.maximumHoldingsPerInvestor != 0) {
            _push(l, FHE.ge(toAfter, cfg.holdings.maximumHoldingsPerInvestor), PropaneCodes.CODE_ABOVE_MAX);
        }
    }

    function _issuanceFails(PropaneAttributes memory ta, euint64 toBal, ebool toNew, euint64 amount)
        private
        returns (ebool f)
    {
        Flags storage flags = _s().config.flags;
        ebool toUS = FHE.eq(ta.region, PropaneRegions.REGION_US);
        f = FHE.or(ta.liquidateOnly, FHE.eq(ta.region, PropaneRegions.REGION_FORBIDDEN));
        if (flags.forceAccredited) f = FHE.or(f, FHE.not(ta.accredited));
        if (flags.forceAccreditedUS) f = FHE.or(f, FHE.and(toUS, FHE.not(ta.accredited)));
        // Issuance has no sender to free a slot: a synthetic sender that is partial, non-US,
        // non-EU and non-accredited makes every cap apply to a new holder, as in the prior art.
        ebool no = FHE.asEbool(false);
        PropaneCapInput memory i = PropaneCapInput({
            fromUS: no,
            fromEU: no,
            fromAccredited: no,
            fromQualified: no,
            fromPartial: FHE.asEbool(true),
            fromFull: no,
            fromRegion: FHE.asEuint8(PropaneRegions.REGION_NONE),
            fromEuCountry: FHE.asEuint8(0),
            toUS: toUS,
            toEU: FHE.eq(ta.region, PropaneRegions.REGION_EU),
            toJP: FHE.eq(ta.region, PropaneRegions.REGION_JP),
            toAccredited: ta.accredited,
            toQualified: ta.qualified,
            toNew: toNew,
            toEuCountry: ta.euCountry,
            isIssuance: true
        });
        (ebool regional, ebool global,) = _capChecks(i);
        f = FHE.or(f, FHE.or(regional, global));
        f = FHE.or(f, _issuanceHoldingFails(ta, toBal, amount, _s().config));
    }

    function _issuanceHoldingFails(PropaneAttributes memory ta, euint64 toBal, euint64 amount, Config storage cfg)
        private
        returns (ebool f)
    {
        f = FHE.asEbool(false);
        euint64 toAfter = FHE.add(toBal, amount);
        if (cfg.holdings.minUSTokens != 0) {
            ebool toUS = FHE.eq(ta.region, PropaneRegions.REGION_US);
            f = FHE.or(f, FHE.and(toUS, FHE.lt(toAfter, cfg.holdings.minUSTokens)));
        }
        if (cfg.holdings.minEUTokens != 0) {
            ebool toEU = FHE.eq(ta.region, PropaneRegions.REGION_EU);
            f = FHE.or(f, FHE.and(toEU, FHE.lt(toAfter, cfg.holdings.minEUTokens)));
        }
        if (cfg.holdings.minimumHoldingsPerInvestor != 0) {
            f = FHE.or(f, FHE.lt(toAfter, cfg.holdings.minimumHoldingsPerInvestor));
        }
        if (cfg.holdings.maximumHoldingsPerInvestor != 0) {
            f = FHE.or(f, FHE.ge(toAfter, cfg.holdings.maximumHoldingsPerInvestor));
        }
    }

    function _push(Ladder memory l, ebool f, uint8 k) private pure {
        l.f[l.n] = f;
        l.k[l.n] = k;
        l.n++;
    }

    function _fold(Ladder memory l) private returns (ebool fail, euint8 code) {
        fail = FHE.asEbool(false);
        code = FHE.asEuint8(PropaneCodes.CODE_VALID);
        for (uint256 i = l.n; i > 0; i--) {
            code = FHE.select(l.f[i - 1], FHE.asEuint8(l.k[i - 1]), code);
            fail = FHE.or(fail, l.f[i - 1]);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Census maintenance
    // ---------------------------------------------------------------------------------------------

    function _censusMove(Ctx memory c, euint64 effective) private {
        // A self-transfer changes no holding. Without this guard a full-balance self-transfer
        // would count the holder as leaving and let any holder deflate the census at will.
        if (c.from == c.to) {
            ebool no = FHE.asEbool(false);
            _move(c.fa, c.ta, no, no);
            return;
        }
        ebool nz = FHE.ne(effective, uint64(0));
        ebool leave = c.fromPlatform ? FHE.asEbool(false) : FHE.and(FHE.eq(c.fromBal, effective), nz);
        ebool enter = c.toPlatform ? FHE.asEbool(false) : FHE.and(c.toNew, nz);
        _move(c.fa, c.ta, leave, enter);
    }

    /// @dev Hands a move to the census service. Every handle is granted transiently; the census
    ///      rewrites every counter whether or not either flag is set.
    function _move(PropaneAttributes memory leaveAttrs, PropaneAttributes memory enterAttrs, ebool leave, ebool enter)
        private
    {
        address census = _service(PropaneServices.SVC_CENSUS);
        _lend(leaveAttrs, census);
        _lend(enterAttrs, census);
        FHE.allowTransient(leave, census);
        FHE.allowTransient(enter, census);
        IPropaneCensus(census).applyMove(leaveAttrs, enterAttrs, leave, enter);
    }

    function _lend(PropaneAttributes memory a, address to) private {
        FHE.allowTransient(a.region, to);
        FHE.allowTransient(a.euCountry, to);
        FHE.allowTransient(a.accredited, to);
        FHE.allowTransient(a.qualified, to);
        FHE.allowTransient(a.liquidateOnly, to);
    }

    // ---------------------------------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------------------------------

    function _bal(address wallet) private returns (euint64 b) {
        b = IPropaneSecurityToken(_service(PropaneServices.SVC_TOKEN)).confidentialBalanceOf(wallet);
        if (!FHE.isInitialized(b)) b = FHE.asEuint64(0);
    }

    function _attrs(address wallet) private returns (PropaneAttributes memory) {
        return _initAttrs(IPropaneRegistry(_service(PropaneServices.SVC_REGISTRY)).attributes(wallet));
    }

    function _initAttrs(PropaneAttributes memory a) private returns (PropaneAttributes memory) {
        if (!FHE.isInitialized(a.region)) a.region = FHE.asEuint8(PropaneRegions.REGION_NONE);
        if (!FHE.isInitialized(a.euCountry)) a.euCountry = FHE.asEuint8(0);
        if (!FHE.isInitialized(a.accredited)) a.accredited = FHE.asEbool(false);
        if (!FHE.isInitialized(a.qualified)) a.qualified = FHE.asEbool(false);
        if (!FHE.isInitialized(a.liquidateOnly)) a.liquidateOnly = FHE.asEbool(false);
        return a;
    }

    function _toKeeper(euint8 v) private {
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
    }

    function _toKeeper(euint64 v) private {
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
    }
}
