# Staking Templates

## Credits

These contracts are based off Synthetix's original staking contracts. You can find them on their [GitHub](https://github.com/Synthetixio/synthetix).

## Contracts

There are currently two contracts in the repo.

1. Standard staking. Allows one staking token and one reward token.
2. Multi-reward staking. Allows one staking token and multiple reward tokens.

## TBD

The multi-reward staking needs the following additions and optimizations:
- General gas optimizations. Review data structure and determine if most efficient for 2+ tokens. Identify any other potential savings.
- Add and remove tokens. Allow the `distributor` address to adjust the tokens. Add token is present but untested.
- Enable `distributor` address to withdraw ERC20 tokens in case of error, accidental transfers or on reward token removal.
- Testing for single asset staking pool (Stake.sol)
- Single asset staking doesn't support tax tokens. Please be careful and test thoroughly.