// SPDX-License-Identifier: BUSL-1.1
// Propane Privacy: deployable, upgradeable roles service.
// @author adiii.eth

pragma solidity 0.8.28;

import {PropaneMaintainer} from "./PropaneMaintainer.sol";

/// @title PropaneMaintainerService
/// @notice Deployable roles service. All behaviour is in PropaneMaintainer.
contract PropaneMaintainerService is PropaneMaintainer {}
