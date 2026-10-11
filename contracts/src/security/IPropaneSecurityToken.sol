//SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ebool, euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

/*security token | confidential balances, no rules of its own*/
/// @title IPropaneSecurityToken
/// @author Propane
/// @notice Confidential security token. Holds encrypted balances and delegates every decision to
///         the compliance service resolved at call time. Shaped after ERC-7943; the deviations
///         forced by encrypted amounts are listed in Technical Note 07.
interface IPropaneSecurityToken {
    event PropaneConfidentialTransfer(address indexed from, address indexed to, euint64 amount);
    event PropaneIssued(address indexed to, euint64 amount);
    event PropaneBurned(address indexed from, euint64 amount);
    event PropaneForcedTransfer(address indexed from, address indexed to, euint64 amount);
    event PropaneFrozen(address indexed account, euint64 amount);
    event PropanePaused(bool paused);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function confidentialBalanceOf(address account) external view returns (euint64);
    function confidentialTotalSupply() external view returns (euint64);
    function getFrozenTokens(address account) external view returns (euint64);

    function confidentialTransfer(address to, externalEuint64 amount, bytes calldata proof)
        external
        returns (euint64 transferred);
    function confidentialTransfer(address to, euint64 amount) external returns (euint64 transferred);

    function issue(address to, externalEuint64 amount, bytes calldata proof) external returns (euint64 issued);
    function burn(address from, externalEuint64 amount, bytes calldata proof) external returns (euint64 burned);
    function forcedTransfer(address from, address to, externalEuint64 amount, bytes calldata proof)
        external
        returns (euint64 moved);
    function setFrozenTokens(address account, externalEuint64 amount, bytes calldata proof) external;
    function setPaused(bool paused) external;

    /// @notice Balance minus frozen tokens, granted transiently to the compliance service.
    function computeAvailable(address account) external returns (euint64);
}
