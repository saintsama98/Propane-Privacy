// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract SmokeCounter is ZamaEthereumConfig {
    euint64 public c;

    function add(externalEuint64 x, bytes calldata proof) external {
        c = FHE.add(c, FHE.fromExternal(x, proof));
        FHE.allowThis(c);
        FHE.allow(c, msg.sender);
    }
}

contract FheSmokeTest is FhevmTest {
    function test_fheStackWorks() public {
        SmokeCounter s = new SmokeCounter();
        (externalEuint64 h, bytes memory p) = encryptUint64(41, address(this), address(s));
        s.add(h, p);
        (h, p) = encryptUint64(1, address(this), address(s));
        s.add(h, p);
        assertEq(decrypt(s.c()), 42);
    }
}
