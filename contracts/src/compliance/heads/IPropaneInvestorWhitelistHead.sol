//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IPropaneRuleHead} from "../../interfaces/IPropaneServices.sol";
import {externalEbool, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/// @title IPropaneInvestorWhitelistHead
/// @author Propane
/// @notice Rule head, offering-level admission: the recipient must hold an encrypted admission flag. An independent module resolved by the engine.
interface IPropaneInvestorWhitelistHead is IPropaneRuleHead {
    function setAdmitted(address wallet, externalEbool admitted, bytes calldata proof) external;
}
