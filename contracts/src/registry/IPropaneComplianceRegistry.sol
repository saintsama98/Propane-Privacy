//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {externalEbool, externalEuint8} from "encrypted-types/EncryptedTypes.sol";
import {IPropaneRegistry} from "../interfaces/IPropaneServices.sol";

/*compliance registry | wallet registration and the encrypted attested record read by every rule*/
/// @title IPropaneComplianceRegistry
/// @author Propane
/// @notice Write surface of the registry. Attributes arrive as encrypted inputs from the transfer
///         agent; the registry never sees them in the clear and stores no personal data in any form.
interface IPropaneComplianceRegistry is IPropaneRegistry {
    struct EncryptedAttributesInput {
        externalEuint8 region;
        externalEuint8 euCountry;
        externalEbool accredited;
        externalEbool qualified;
        externalEbool liquidateOnly;
    }

    event PropaneWalletRegistered(address indexed wallet);
    event PropaneAttributesUpdated(address indexed wallet);
    event PropaneWalletDeregistered(address indexed wallet);

    function registerWallet(address wallet, EncryptedAttributesInput calldata attrs, bytes calldata proof) external;
    function updateAttributes(address wallet, EncryptedAttributesInput calldata attrs, bytes calldata proof) external;
    function deregisterWallet(address wallet) external;
}
