//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IPropaneRuleHead} from "../../../interfaces/IPropaneServices.sol";
import {externalEbool, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/// @title IPropaneInvestorBlacklistHead
/// @author Propane
/// @notice Rule head, denied investors: neither party may be on the encrypted deny list. An independent module resolved by the engine.
interface IPropaneInvestorBlacklistHead is IPropaneRuleHead {
    function setBlacklisted(address wallet, externalEbool listed, bytes calldata proof) external;
}
