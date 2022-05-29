// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { expect } from "chai";
import { makeSwap, TOKEN_ABI } from "../scripts/utils";

const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const QFI = "0x6fe88a211863d0d818608036880c9a4b0ea86795";

describe("Stake", function () {
    it("Should allow add tokens, remove tokens, stake, and withdraw", async function () {
        // Hardhat always runs the compile task when running scripts with its command
        // line interface.
        //
        // If this script is run directly using `node` you may want to call compile
        // manually to make sure everything is compiled
        // await hre.run('compile');

        // Get signers
        const accounts = await ethers.getSigners();

        const Stake = await ethers.getContractFactory("SingleAssetStake");
        const stake = await Stake.deploy(
            accounts[0].address,
            QFI,
            QFI,
            7
        );

        await stake.deployed();

        await makeSwap(accounts[0], [WETH, QFI], '4.0');
        await makeSwap(accounts[1], [WETH, QFI], '5.0');

        const qfiContract = new ethers.Contract(QFI, TOKEN_ABI, ethers.provider);

        const qfiBalance = await qfiContract.balanceOf(accounts[0].address);
        const qfiBalance2 = await qfiContract.balanceOf(accounts[1].address);

        const stakeAmount = qfiBalance.div(4);
        const depositAmount = qfiBalance.sub(stakeAmount);

        await qfiContract.connect(accounts[0]).transfer(stake.address, depositAmount);

        await (await stake.connect(accounts[0]).notifyRewardAmount(depositAmount)).wait();

        await (await qfiContract.connect(accounts[0]).approve(stake.address, stakeAmount)).wait();
        await (await qfiContract.connect(accounts[1]).approve(stake.address, qfiBalance2.div(3))).wait();

        await stake.connect(accounts[0]).stake(stakeAmount);
        await stake.connect(accounts[1]).stake(qfiBalance2.div(3));
        console.log(await stake.getRewardForDuration());

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        console.log(await stake.earned(accounts[0].address));
        console.log(await stake.earned(accounts[1].address));

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        console.log(await stake.earned(accounts[0].address));
        console.log(await stake.earned(accounts[1].address));

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        console.log(await stake.earned(accounts[0].address));
        console.log(await stake.earned(accounts[1].address));

        await ethers.provider.send("evm_increaseTime", [86400]);
        await ethers.provider.send("evm_mine", []);

        console.log(await stake.earned(accounts[0].address));
        console.log(await stake.earned(accounts[1].address));
        await stake.connect(accounts[0]).exit();
        await stake.connect(accounts[1]).withdraw(await stake.balanceOf(accounts[1].address));
        await stake.connect(accounts[1]).getReward();
    });
});
  