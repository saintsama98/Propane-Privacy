//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {FHE, ebool, euint8} from "@fhevm/solidity/lib/FHE.sol";
import {IPropaneComplianceRegistry} from "./IPropaneComplianceRegistry.sol";
import {PropaneComplianceRegistryStore} from "../silo/storage/propaneComplianceRegistryStore.sol";
import {PropaneServiceConsumer} from "../common/PropaneServiceConsumer.sol";
import {PropaneRoles, PropaneServices} from "../common/PropaneConstants.sol";
import {IPropaneCompliance, PropaneAttributes} from "../interfaces/IPropaneServices.sol";

/*compliance registry | wallet registration and the encrypted attested record read by every rule*/
/// @title PropaneComplianceRegistry
/// @author Propane
/// @notice Holds whether a wallet is registered (public) and its attested attributes (encrypted).
///         Every attribute change is reported to the compliance service before it takes effect,
///         because a change of region or accreditation moves a holder between census counters.
contract PropaneComplianceRegistry is
    PropaneServiceConsumer,
    PropaneComplianceRegistryStore,
    IPropaneComplianceRegistry
{
    function initialize(address locator_) external initializer {
        __PropaneServiceConsumer_init(locator_);
    }

    function registerWallet(address wallet, EncryptedAttributesInput calldata attrs, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        require(wallet != address(0), "Zero wallet");
        WalletRecord storage r = _complianceRegistry().records[wallet];
        require(!r.registered, "Already registered");
        bool known = FHE.isInitialized(r.attrs.region);
        r.registered = true;
        if (!known) _complianceRegistry().wallets.push(wallet);
        _write(wallet, r, attrs, proof);
        emit PropaneWalletRegistered(wallet);
    }

    function updateAttributes(address wallet, EncryptedAttributesInput calldata attrs, bytes calldata proof)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        WalletRecord storage r = _complianceRegistry().records[wallet];
        require(r.registered, "Not registered");
        _write(wallet, r, attrs, proof);
        emit PropaneAttributesUpdated(wallet);
    }

    /// @notice Stops the wallet from receiving. Attributes are kept so that the holder is still
    ///         counted correctly in the census until it exits.
    function deregisterWallet(address wallet)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        WalletRecord storage r = _complianceRegistry().records[wallet];
        require(r.registered, "Not registered");
        r.registered = false;
        emit PropaneWalletDeregistered(wallet);
    }

    function isRegistered(address wallet) external view returns (bool) {
        return _complianceRegistry().records[wallet].registered;
    }

    function walletCount() external view returns (uint256) {
        return _complianceRegistry().wallets.length;
    }

    function walletAt(uint256 index) external view returns (address) {
        return _complianceRegistry().wallets[index];
    }

    function attributes(address wallet) external view returns (PropaneAttributes memory) {
        return _complianceRegistry().records[wallet].attrs;
    }

    /// @notice Re-grants the current compliance service access to stored attributes, for use after
    ///         the compliance service has been replaced.
    function regrantCompliance(address[] calldata wallets)
        external
        onlyRoles2(PropaneRoles.ROLE_OFFICER, PropaneRoles.ROLE_SUPER_OWNER)
    {
        address compliance = _service(PropaneServices.SVC_COMPLIANCE);
        for (uint256 i = 0; i < wallets.length; i++) {
            PropaneAttributes storage a = _complianceRegistry().records[wallets[i]].attrs;
            if (FHE.isInitialized(a.region)) {
                FHE.allow(a.region, compliance);
                FHE.allow(a.euCountry, compliance);
                FHE.allow(a.accredited, compliance);
                FHE.allow(a.qualified, compliance);
                FHE.allow(a.liquidateOnly, compliance);
            }
        }
    }

    function _write(address wallet, WalletRecord storage r, EncryptedAttributesInput calldata i, bytes calldata proof)
        private
    {
        PropaneAttributes memory next = PropaneAttributes({
            region: FHE.fromExternal(i.region, proof),
            euCountry: FHE.fromExternal(i.euCountry, proof),
            accredited: FHE.fromExternal(i.accredited, proof),
            qualified: FHE.fromExternal(i.qualified, proof),
            liquidateOnly: FHE.fromExternal(i.liquidateOnly, proof)
        });

        address compliance = _service(PropaneServices.SVC_COMPLIANCE);
        address keeper = _recordKeeper();
        address census = _serviceOrZero(PropaneServices.SVC_CENSUS);
        _grant(next.region, compliance, keeper, census);
        _grant(next.euCountry, compliance, keeper, census);
        _grant(next.accredited, compliance, keeper, census);
        _grant(next.qualified, compliance, keeper, census);
        _grant(next.liquidateOnly, compliance, keeper, census);

        // The census moves before the record does: the engine reads the holder's balance and the
        // old and new categories, and applies a possibly-zero delta to every counter.
        IPropaneCompliance(compliance).onAttributesChanged(wallet, r.attrs, next);
        r.attrs = next;
    }

    function _grant(euint8 v, address compliance, address keeper, address census) private {
        FHE.allowThis(v);
        FHE.allow(v, compliance);
        if (keeper != address(0)) FHE.allow(v, keeper);
        if (census != address(0)) FHE.allow(v, census);
    }

    function _grant(ebool v, address compliance, address keeper, address census) private {
        FHE.allowThis(v);
        FHE.allow(v, compliance);
        if (keeper != address(0)) FHE.allow(v, keeper);
        if (census != address(0)) FHE.allow(v, census);
    }
}
