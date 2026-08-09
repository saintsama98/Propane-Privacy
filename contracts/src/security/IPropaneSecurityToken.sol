//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// TODO: src/utils/CommonUtils.sol does not exist yet; restore once written.
// import {CommonUtils} from "../utils/CommonUtils.sol";
abstract contract IPropaneSecurityToken is IERC20, Initializable {
    /**
     * @notice this is security for propane and aimed for fund side sustainability, no capital movement is
     * supposed to take place at any level
     * @dev keep this contract solely to hold and mint securities, receipts respectively
     * @notice core role of the token contract:
     * compliance necessarily callbacks to token contract for worthy checks and balance requirements
     */
}
