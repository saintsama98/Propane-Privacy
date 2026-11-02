// SPDX-License-Identifier: MIT
// Propane Privacy: interface of the account-shape head.
// @author adiii.eth

pragma solidity 0.8.28;

import {IPropaneRuleHead} from "../../interfaces/IPropaneServices.sol";

/// @title IPropaneInvestorEOAHead
/// @notice Rule head, account-shape rule: the recipient must be an externally owned account unless it is a platform wallet. An independent module resolved by the engine.
interface IPropaneInvestorEOAHead is IPropaneRuleHead {}
