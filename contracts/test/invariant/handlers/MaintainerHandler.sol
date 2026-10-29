// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PropaneMaintainer} from "../../../src/maintainer/PropaneMaintainer.sol";

contract InvariantMaintainerHarness is PropaneMaintainer {}

/// @dev Drives arbitrary role calls from a fixed actor set, including the root.
contract MaintainerHandler is Test {
    InvariantMaintainerHarness internal m;
    address[] public actors;
    uint256 public superOwnerTransfers;

    constructor(InvariantMaintainerHarness _m, address[] memory _actors) {
        m = _m;
        actors = _actors;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function add(uint256 callerSeed, uint256 targetSeed, uint8 role) external {
        vm.prank(actors[callerSeed % actors.length]);
        try m.addUniversalRole(actors[targetSeed % actors.length], role) {} catch {}
    }

    function remove(uint256 callerSeed, uint256 targetSeed) external {
        vm.prank(actors[callerSeed % actors.length]);
        try m.removeUniversalRole(actors[targetSeed % actors.length]) {} catch {}
    }

    function transfer(uint256 callerSeed, uint256 targetSeed) external {
        vm.prank(actors[callerSeed % actors.length]);
        try m.transferSuperOwner(actors[targetSeed % actors.length]) {
            superOwnerTransfers++;
        } catch {}
    }
}
