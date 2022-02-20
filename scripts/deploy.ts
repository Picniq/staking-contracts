// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { makeSwap, TOKEN_ABI } from "./utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const SAITAMA = "0xC795fBa221f7920F1C6ac0f1598886742D8Ea661";
const SHIB = "0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // Get signers
  const accounts = await ethers.getSigners();

  // We get the contract to deploy
  const MultiStake = await ethers.getContractFactory("MultiRewardsStake");
  const multiStake = await MultiStake.deploy(
    accounts[0].address,
    [SAITAMA, SHIB],
    SAITAMA
  );

  await multiStake.deployed();

  await makeSwap(accounts[0], [WETH, SAITAMA], '4.0');
  await makeSwap(accounts[0], [WETH, SHIB], '4.0');

  await makeSwap(accounts[1], [WETH, SAITAMA], '1.0');

  await ethers.provider.send("evm_mine", []);

  const qfiContract = new ethers.Contract(SAITAMA, TOKEN_ABI, ethers.provider);
  const shibContract = new ethers.Contract(SHIB, TOKEN_ABI, ethers.provider);

  const qfiBalance = await qfiContract.balanceOf(accounts[0].address);
  const shibBalance = await shibContract.balanceOf(accounts[0].address);

  const stakeAmount = qfiBalance.div(4);
  const depositAmount = qfiBalance.sub(stakeAmount);
  const depositAmount2 = await qfiContract.balanceOf(accounts[1].address);

  await qfiContract.connect(accounts[0]).transfer(multiStake.address, depositAmount);
  await shibContract.connect(accounts[0]).transfer(multiStake.address, shibBalance);

  await ethers.provider.send("evm_mine", []);

  await (await multiStake.connect(accounts[0]).notifyRewardAmount([depositAmount, shibBalance])).wait();

  await (await qfiContract.connect(accounts[0]).approve(multiStake.address, stakeAmount)).wait();
  await (await qfiContract.connect(accounts[1]).approve(multiStake.address, depositAmount2)).wait();

  await (await multiStake.connect(accounts[0]).stake(stakeAmount)).wait();
  await (await multiStake.connect(accounts[1]).stake(depositAmount2)).wait();

  console.log(await multiStake.getRewardForDuration());

  for (let i = 0; i < 6500; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  await ethers.provider.send("evm_increaseTime", [86400]);

  console.log(await multiStake.earned(accounts[0].address));
  console.log(await multiStake.earned(accounts[1].address));

  for (let i = 0; i < 6500; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  await ethers.provider.send("evm_increaseTime", [86400]);

  console.log(await multiStake.earned(accounts[0].address));
  console.log(await multiStake.earned(accounts[1].address));

  for (let i = 0; i < 6500; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  await ethers.provider.send("evm_increaseTime", [86400]);

  console.log(await multiStake.earned(accounts[0].address));
  console.log(await multiStake.earned(accounts[1].address));

  for (let i = 0; i < 6500; i++) {
    await ethers.provider.send("evm_mine", []);
  }
  await ethers.provider.send("evm_increaseTime", [86400]);

  console.log(await multiStake.earned(accounts[0].address));
  console.log(await multiStake.earned(accounts[1].address));

  await (await multiStake.connect(accounts[0]).getReward()).wait();

  console.log(await qfiContract.balanceOf(accounts[0].address));

  console.log(await multiStake.getRewardForDuration());

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
