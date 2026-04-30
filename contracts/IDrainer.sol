// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IDrainer
/// @notice Interface imposed by APT28 leadership (per README spec).
/// @dev Note: this interface intentionally diverges from the original stub
///      provided in the repository (which used a single-argument attack(nonce)).
///      The README is the authoritative spec and matches FairCasino.play(guess, round, nonce).
interface IDrainer {
    /**
     * @notice Main entry point required by APT28 monitoring bots.
     * @param _guess Predicted winning number calculated via storage/oracle analysis.
     * @param _round Current active round ID of the target contract.
     * @param _nonce Cryptographic signature mined to satisfy the protocol's required
     *               computational difficulty threshold (last 2 bytes of keccak256
     *               must equal 0xbeef).
     */
    function attack(uint256 _guess, uint256 _round, uint256 _nonce) external payable;

    /**
     * @notice Mandatory Splitter module.
     * @dev Must redistribute the entire balance of the attack contract to the 3 lieutenants
     *      according to the schema 50% / 30% / 20%.
     */
    function distribute() external;
}
