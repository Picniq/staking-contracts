// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { makeSwap, TOKEN_ABI } from "./utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const QFI = "0x6fe88a211863d0d818608036880c9a4b0ea86795";
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
    [QFI, SHIB],
    QFI
  );

  await multiStake.deployed();

  await makeSwap(accounts[0], [WETH, QFI], '4.0');
  await makeSwap(accounts[0], [WETH, SHIB], '4.0');

  await makeSwap(accounts[1], [WETH, QFI], '1.0');

  await ethers.provider.send("evm_mine", []);

  const qfiContract = new ethers.Contract(QFI, TOKEN_ABI, ethers.provider);
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
