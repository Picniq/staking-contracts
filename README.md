# Staking Templates

## Credits

These contracts are based off Synthetix's original staking contracts. You can find them on their [GitHub](https://github.com/Synthetixio/synthetix).

## Contracts

There are currently three contracts in the repo.

1. Standard staking. Allows one staking token and one reward token.
2. Multi-reward staking. Allows one staking token and multiple reward tokens.
3. NFTMultiStake. A multi-reward staking contract for NFTs.

## TBD

The multi-reward staking needs the following additions and optimizations:
- Testing for single asset staking pool (Stake.sol)
- Testing for NFT staking pool (NFTMultiStake.sol)
- Single asset staking doesn't support tax tokens. Please be careful and test thoroughly.