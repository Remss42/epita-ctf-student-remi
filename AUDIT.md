# AUDIT

1 - J'ai d'abord créé un compte MetaMask, je suis passé sur Sepolia, j'ai récupéré ~0,75 SepoliaETH via Sepolia PoW Faucet, puis j'ai forké le dépôt.

2 - J'ai ensuite regardé le code du contrat cible sur https://sepolia.etherscan.io/address/0xed5415679D46415f6f9a82677F8F4E9ed9D1302b#code (le code source était lisible directement).

J'ai analysé le jeu. Le contrat est un "casino" où on appelle `play(guess, round, nonce)` en payant 0.01 ETH. Si on devine correctement le `winningNumber`, on gagne `min(jackpotReserve/2, 0.1 ETH)`.

3 - Puis j'ai vu qu'il y avait une faille : sur Ethereum, rien n'est vraiment privé. Même les variables marquées `private` ou `immutable` sont lisibles publiquement (storage off-chain, bytecode déployé, arguments du constructeur publiés sur Etherscan). J'ai donc pu récupérer les 3 valeurs "secrètes" du casino directement sur Etherscan.

4 - Avec ça j'ai pu recalculer le `winningNumber` exactement comme le contrat le fait :
```
winningNumber = keccak256(secretTarget XOR price, gameSalt, currentRound)
```

Il restait ensuite une 2ème protection : un proof-of-work qui demande que les 2 derniers octets de `keccak256(msg.sender, nonce, guess, round)` valent `0xbeef`. C'est 1 chance sur 65536, ~10 secondes en Python. J'ai écrit un script `scripts/mine.py` qui lit l'état de la chaîne (round + prix), calcule le guess, et mine le nonce.

5 - J'ai écrit `Drainer.sol` qui implémente l'interface du brief (`attack(_guess, _round, _nonce)` + `distribute()`). La fonction `attack()` :
   - envoie 0.01 ETH au casino avec mes valeurs précalculées
   - reçoit les 0.1 ETH du gain
   - redistribue tout en 50% / 30% / 20% aux 3 lieutenants

-> Le tout dans la même transaction, pour respecter l'atomicité.

6 - Déploiement et vérification du Drainer sur Sepolia via Remix :
J'ai d'abord compilé le Drainer puis je l'ai déployé avec mon compte MetaMask comme Environment. J'ai ensuite récupéré l'adresse du contrat, et j'ai pu lancer le script Python pour obtenir le `round`, le `nonce` et le `guess` à passer à `attack()`. Ensuite j'ai lancé l'attaque et j'ai gagné mes 0.1 ETH, que le contrat a redistribué automatiquement aux 3 destinataires (0.05 / 0.03 / 0.02 ETH).

   - Adresse : `0xbBD27f47F7fF02c2a9fD0DA4f88196F1F82cd6ba`
   - Vérifié sur Etherscan : "Source Code Verified — Exact Match"

## Conclusion

L'attaque a marché parce que le créateur du `FairCasino` n'avait pas vraiment de code secret : tout était devinable et calculable.

