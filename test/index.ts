import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { approve, getBalance, makeSwap, transfer } from "../scripts/utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const UST = "0xa47c8bf37f92aBed4A126BDA807A7b7498661acD";
const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
const SHIB = "0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE";
const QFI = "0x6fE88a211863D0d818608036880c9A4b0EA86795";

describe("MultiRewardsStake", function () {
  it("Should allow add tokens, remove tokens, stake, and withdraw", async function () {
    const accounts: SignerWithAddress[] = await ethers.getSigners();
    const Stake = await ethers.getContractFactory("MultiRewardsStake");
    const stake = await Stake.deploy(
      [LINK, SHIB],
      UST
    );
    await stake.deployed();

    console.log(`Deployed: ${stake.address}`);

    expect(await stake.totalRewardTokens()).to.equal(2);

    await makeSwap(accounts[0], [WETH, LINK], '4.0');
    await makeSwap(accounts[0], [WETH, SHIB], '4.0');
    await makeSwap(accounts[0], [WETH, UST], '1.0');
    await makeSwap(accounts[1], [WETH, UST], '1.0');

    await ethers.provider.send('evm_mine', []);

    let linkBalance = await getBalance(LINK, accounts[0].address);
    let shibBalance = await getBalance(SHIB, accounts[0].address);
    const ustBalance = await getBalance(UST, accounts[0].address);

    await approve(LINK, accounts[0], stake.address, linkBalance);
    await approve(SHIB, accounts[0], stake.address, shibBalance);

    await stake.depositRewardTokens([linkBalance, shibBalance]);

    await ethers.provider.send('evm_mine', []);

    await makeSwap(accounts[0], [WETH, LINK], '4.0');
    await makeSwap(accounts[0], [WETH, SHIB], '4.0');

    await ethers.provider.send('evm_mine', []);

    await approve(LINK, accounts[0], stake.address, linkBalance);
    await approve(SHIB, accounts[0], stake.address, shibBalance);

    await ethers.provider.send('evm_mine', []);

    linkBalance = await getBalance(LINK, accounts[0].address);
    shibBalance = await getBalance(SHIB, accounts[0].address);

    await stake.depositRewardTokens([linkBalance, shibBalance]);

    await ethers.provider.send('evm_mine', []);

    const stakeAmount = ustBalance.div(2);

    await approve(UST, accounts[0], stake.address, stakeAmount);
    await approve(UST, accounts[1], stake.address, await getBalance(UST, accounts[1].address));
    await stake.connect(accounts[0]).stake(stakeAmount);
    await stake.connect(accounts[1]).stake(await getBalance(UST, accounts[1].address));

    await ethers.provider.send('evm_mine', []);
    
    const earned1 = await stake.earned(accounts[0].address);
    const earned2 = await stake.earned(accounts[1].address);

    expect(Number(ethers.utils.formatUnits(earned1[0], 'gwei'))).to.greaterThan(0);
    expect(Number(ethers.utils.formatUnits(earned1[1], 'gwei'))).to.greaterThan(0);
    expect(Number(ethers.utils.formatUnits(earned2[0], 'gwei'))).to.greaterThan(0);
    expect(Number(ethers.utils.formatUnits(earned2[1], 'gwei'))).to.greaterThan(0);

    await ethers.provider.send('evm_mine', []);
    await ethers.provider.send('evm_mine', []);
    await ethers.provider.send('evm_mine', []);
    
    await stake.connect(accounts[0]).exit();
    await stake.connect(accounts[1]).exit();

    const leftover = await stake.totalSupply();

    expect(Number(leftover)).to.equal(0);

    await stake.connect(accounts[0]).transferOwnership(accounts[1].address);

    await ethers.provider.send('evm_mine', []);

    expect(await stake.owner()).to.equal(accounts[1].address);

    await makeSwap(accounts[1], [WETH, QFI], '1.0');
    await transfer(QFI, accounts[1], stake.address, await getBalance(QFI, accounts[1].address));
    await stake.connect(accounts[1]).addRewardToken(QFI);

    expect((await stake.getRewardTokens()).length).to.equal(3);

    await ethers.provider.send('evm_mine', []);

    await approve(UST, accounts[0], stake.address, stakeAmount);
    await stake.connect(accounts[0]).stake(stakeAmount);

    await ethers.provider.send('evm_mine', []);

    const rewardPerToken = await stake.rewardPerToken();
    expect(Number(rewardPerToken[0])).to.greaterThan(0);
    expect(Number(rewardPerToken[1])).to.greaterThan(0);
    expect(Number(rewardPerToken[2])).to.greaterThan(0);
  
  });
});