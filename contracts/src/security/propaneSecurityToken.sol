//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {PropaneServiceConsumer} from "../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices} from "../common/PropaneConstants.sol";
import {IPropaneCompliance, IPropaneRegistry} from "../interfaces/IPropaneServices.sol";
import {IPropaneSecurityToken} from "./IPropaneSecurityToken.sol";

/*security token | confidential balances, no rules of its own*/
/// @title PropaneSecurityToken
/// @author Propane
/// @notice Holds encrypted balances and nothing else. Every movement is passed to the compliance
///         service, which returns the amount that may move: the requested amount or zero. A refused
///         transfer does not revert, so a failed compliance check is not published (Note 05, R5).
contract PropaneSecurityToken is PropaneServiceConsumer, IPropaneSecurityToken {
    /// @custom:storage-location erc7201:propane.storage.SecurityToken
    struct SecurityTokenStorage {
        string name;
        string symbol;
        uint8 decimals;
        bool paused;
        euint64 totalSupply;
        mapping(address account => euint64) balances;
        mapping(address account => euint64) frozen;
    }

    // erc7201("propane.storage.SecurityToken")
    bytes32 private constant SECURITY_TOKEN_STORAGE =
        0x46e8a8606f495afd6af4fc4b521c0535f9e42c2f654d43b5a11c73e2059f5700;

    error PropaneTokenPaused();
    error PropaneInvalidReceiver(address to);

    function _t() private pure returns (SecurityTokenStorage storage $) {
        bytes32 s = SECURITY_TOKEN_STORAGE;
        assembly {
            $.slot := s
        }
    }

    function initialize(address locator_, string calldata name_, string calldata symbol_, uint8 decimals_)
        external
        initializer
    {
        __PropaneServiceConsumer_init(locator_);
        SecurityTokenStorage storage $ = _t();
        $.name = name_;
        $.symbol = symbol_;
        $.decimals = decimals_;
    }

    // ---------------------------------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------------------------------

    function name() external view returns (string memory) {
        return _t().name;
    }

    function symbol() external view returns (string memory) {
        return _t().symbol;
    }

    function decimals() external view returns (uint8) {
        return _t().decimals;
    }

    function paused() external view returns (bool) {
        return _t().paused;
    }

    function confidentialBalanceOf(address account) external view returns (euint64) {
        return _t().balances[account];
    }

    /// @notice Decryptable by the record keeper only. Publishing the supply would let an observer
    ///         difference it across issuances and burns.
    function confidentialTotalSupply() external view returns (euint64) {
        return _t().totalSupply;
    }

    function getFrozenTokens(address account) external view returns (euint64) {
        return _t().frozen[account];
    }

    // ---------------------------------------------------------------------------------------------
    // Holder paths
    // ---------------------------------------------------------------------------------------------

    function confidentialTransfer(address to, externalEuint64 amount, bytes calldata proof)
        external
        returns (euint64 transferred)
    {
        return _transfer(msg.sender, to, FHE.fromExternal(amount, proof));
    }

    function confidentialTransfer(address to, euint64 amount) external returns (euint64 transferred) {
        require(FHE.isSenderAllowed(amount), "Amount not allowed");
        return _transfer(msg.sender, to, amount);
    }

    // ---------------------------------------------------------------------------------------------
    // Issuer and transfer-agent paths
    // ---------------------------------------------------------------------------------------------

    function issue(address to, externalEuint64 amount, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OWNER, PropaneRoles.ROLE_OFFICER)
        returns (euint64 issued)
    {
        _requireReceiver(to);
        euint64 amt = FHE.fromExternal(amount, proof);
        IPropaneCompliance compliance = _compliance();
        FHE.allowTransient(amt, address(compliance));
        issued = compliance.validateIssuance(to, amt);

        SecurityTokenStorage storage $ = _t();
        _setBalance(to, FHE.add(_balanceOf(to), issued));
        euint64 supply = FHE.add(_init($.totalSupply), issued);
        $.totalSupply = supply;
        FHE.allowThis(supply);
        _grantRecord(supply);
        _grantParties(issued, to, address(0));
        emit PropaneIssued(to, issued);
    }

    function burn(address from, externalEuint64 amount, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OWNER, PropaneRoles.ROLE_OFFICER)
        returns (euint64 burned)
    {
        euint64 amt = FHE.fromExternal(amount, proof);
        euint64 bal = _balanceOf(from);
        IPropaneCompliance compliance = _compliance();
        FHE.allowTransient(amt, address(compliance));
        FHE.allowTransient(bal, address(compliance));
        burned = compliance.validateBurn(from, amt, bal);

        SecurityTokenStorage storage $ = _t();
        euint64 next = FHE.sub(bal, burned);
        _setBalance(from, next);
        _clampFrozen(from, next);
        euint64 supply = FHE.sub(_init($.totalSupply), burned);
        $.totalSupply = supply;
        FHE.allowThis(supply);
        _grantRecord(supply);
        _grantParties(burned, from, address(0));
        emit PropaneBurned(from, burned);
    }

    /// @notice ERC-7943 forced transfer. Bypasses eligibility and frozen tokens; the census is still
    ///         updated. Seizure is a forced transfer into an issuer platform wallet.
    function forcedTransfer(address from, address to, externalEuint64 amount, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
        returns (euint64 moved)
    {
        // A forced self-transfer changes no holding and would miscount the census.
        require(from != to, "Same account");
        _requireReceiver(to);
        euint64 amt = FHE.fromExternal(amount, proof);
        euint64 bal = _balanceOf(from);
        IPropaneCompliance compliance = _compliance();
        FHE.allowTransient(amt, address(compliance));
        FHE.allowTransient(bal, address(compliance));
        moved = compliance.validateForcedTransfer(from, to, amt, bal);

        euint64 nextFrom = FHE.sub(bal, moved);
        _setBalance(from, nextFrom);
        _clampFrozen(from, nextFrom);
        _setBalance(to, FHE.add(_balanceOf(to), moved));
        _grantParties(moved, from, to);
        emit PropaneForcedTransfer(from, to, moved);
    }

    function setFrozenTokens(address account, externalEuint64 amount, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        euint64 amt = FHE.fromExternal(amount, proof);
        FHE.allowThis(amt);
        FHE.allow(amt, account);
        _grantRecord(amt);
        _t().frozen[account] = amt;
        emit PropaneFrozen(account, amt);
    }

    function setPaused(bool paused_) external onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_OWNER) {
        _t().paused = paused_;
        emit PropanePaused(paused_);
    }

    /// @notice Balance minus frozen tokens, for the compliance pre-check.
    function computeAvailable(address account)
        external
        onlyService(PropaneServices.SVC_COMPLIANCE)
        returns (euint64 available)
    {
        available = _available(account);
        FHE.allowTransient(available, msg.sender);
    }

    /// @notice Re-grants the current compliance service access to balances after it is replaced.
    function regrantCompliance(address[] calldata accounts)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        address compliance = _service(PropaneServices.SVC_COMPLIANCE);
        for (uint256 i = 0; i < accounts.length; i++) {
            euint64 b = _t().balances[accounts[i]];
            if (FHE.isInitialized(b)) FHE.allow(b, compliance);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, euint64 amount) private returns (euint64 moved) {
        if (_t().paused) revert PropaneTokenPaused();
        _requireReceiver(to);
        euint64 available = _available(from);
        IPropaneCompliance compliance = _compliance();
        FHE.allowTransient(amount, address(compliance));
        FHE.allowTransient(available, address(compliance));
        moved = compliance.validateTransfer(from, to, amount, available);

        _setBalance(from, FHE.sub(_balanceOf(from), moved));
        _setBalance(to, FHE.add(_balanceOf(to), moved));
        _grantParties(moved, from, to);
        emit PropaneConfidentialTransfer(from, to, moved);
    }

    /// @dev Registration and platform status are public facts, so refusing an unknown receiver
    ///      with a revert discloses nothing.
    function _requireReceiver(address to) private view {
        if (to == address(0)) revert PropaneInvalidReceiver(to);
        bool ok = IPropaneRegistry(_service(PropaneServices.SVC_REGISTRY)).isRegistered(to)
            || _compliance().isPlatformWallet(to);
        if (!ok) revert PropaneInvalidReceiver(to);
    }

    function _available(address account) private returns (euint64) {
        euint64 bal = _balanceOf(account);
        euint64 fr = _init(_t().frozen[account]);
        return FHE.select(FHE.ge(bal, fr), FHE.sub(bal, fr), FHE.asEuint64(0));
    }

    function _clampFrozen(address account, euint64 balance) private {
        euint64 fr = _t().frozen[account];
        if (!FHE.isInitialized(fr)) return;
        euint64 next = FHE.select(FHE.gt(fr, balance), balance, fr);
        FHE.allowThis(next);
        FHE.allow(next, account);
        _grantRecord(next);
        _t().frozen[account] = next;
    }

    function _setBalance(address account, euint64 value) private {
        FHE.allowThis(value);
        FHE.allow(value, account);
        FHE.allow(value, address(_compliance()));
        // The census reads balances only to recompute itself from chain state (Note 05, R14).
        address census = _serviceOrZero(PropaneServices.SVC_CENSUS);
        if (census != address(0)) FHE.allow(value, census);
        _grantRecord(value);
        _t().balances[account] = value;
    }

    function _grantParties(euint64 amount, address a, address b) private {
        FHE.allowThis(amount);
        if (a != address(0)) FHE.allow(amount, a);
        if (b != address(0)) FHE.allow(amount, b);
        _grantRecord(amount);
    }

    function _grantRecord(euint64 v) private {
        address keeper = _recordKeeper();
        if (keeper != address(0)) FHE.allow(v, keeper);
    }

    function _balanceOf(address account) private returns (euint64) {
        return _init(_t().balances[account]);
    }

    function _init(euint64 v) private returns (euint64) {
        return FHE.isInitialized(v) ? v : FHE.asEuint64(0);
    }

    function _compliance() private view returns (IPropaneCompliance) {
        return IPropaneCompliance(_service(PropaneServices.SVC_COMPLIANCE));
    }
}
