import { expect } from "chai";
import { ethers } from "hardhat";
import { approve, getBalance, makeSwap, transfer } from "../scripts/utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const UST = "0xa47c8bf37f92abed4a126bda807a7b7498661acd";
const SHIB = "0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE";
const LINK = "0x514910771af9ca656af840dff83e8264ecf986ca";

describe("MultiRewardsStake", function () {
  it("Should allow add tokens, remove tokens, stake, and withdraw", async function () {
    const accounts = await ethers.getSigners();

    const Stake = await ethers.getContractFactory("MultiRewardsStake");
    const stake = await Stake.deploy(
      accounts[0].address,
      [UST, SHIB],
      UST
    );
    await stake.deployed();

    // Get required tokens
    await makeSwap(accounts[0], [WETH, UST], '5.0');
    await makeSwap(accounts[0], [WETH, SHIB], '4.0');

    await ethers.provider.send('evm_mine', []);

    const usdtBalance = await getBalance(UST, accounts[0].address);
    const shibBalance = await getBalance(SHIB, accounts[0].address);

    const stakeAmount = usdtBalance.div(5);
    const depositAmount = usdtBalance.sub(stakeAmount);

    await transfer(UST, accounts[0], stake.address, depositAmount);
    await transfer(SHIB, accounts[0], stake.address, shibBalance);

    await ethers.provider.send('evm_mine', []);

    await stake.connect(accounts[0]).notifyRewardAmount([depositAmount, shibBalance]);

    await ethers.provider.send('evm_mine', []);
    
    await approve(UST, accounts[0], stake.address, stakeAmount);
    await stake.connect(accounts[0]).stake(stakeAmount);

    expect(await stake.totalSupply()).to.equal(stakeAmount);
    expect(await stake.totalRewardTokens()).to.equal(2);

    await makeSwap(accounts[0], [WETH, LINK], '4.0');

    await ethers.provider.send('evm_mine', []);

    const earned1 = await stake.earned(accounts[0].address);
    expect(Number(ethers.utils.formatEther(earned1[0]))).to.greaterThan(0);
    expect(Number(ethers.utils.formatEther(earned1[1]))).to.greaterThan(0);

    const linkBalance = await getBalance(LINK, accounts[0].address);

    await transfer(LINK, accounts[0], stake.address, linkBalance);
    
    await stake.connect(accounts[0]).addRewardToken(LINK);

    await ethers.provider.send('evm_mine', []);

    expect(await stake.totalRewardTokens()).to.equal(3);

    const earned2 = await stake.earned(accounts[0].address);

    expect(Number(ethers.utils.formatEther(earned2[0]))).to.greaterThan(0);
    expect(Number(ethers.utils.formatEther(earned2[1]))).to.greaterThan(0);
    expect(Number(ethers.utils.formatEther(earned2[2]))).to.greaterThan(0);

    await stake.connect(accounts[0]).getReward();
  });
});