// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
// import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { expect } from "chai";
// import dotenv from "dotenv";
// import { ethers, upgrades } from "hardhat";
// import { Fees, MockFees__factory, MockStakeTogether } from "../../typechain";
// import connect from "../utils/connect";
// import { feesFixture } from "./FeesFixture";

// dotenv.config();

// describe("Fees", function () {
//   let feesContract: Fees;
//   let feesProxy: string;
//   let stContract: MockStakeTogether;
//   let stProxy: string;
//   let owner: HardhatEthersSigner;
//   let user1: HardhatEthersSigner;
//   let user2: HardhatEthersSigner;
//   let user3: HardhatEthersSigner;
//   let user4: HardhatEthersSigner;
//   let user5: HardhatEthersSigner;
//   let user6: HardhatEthersSigner;
//   let user7: HardhatEthersSigner;
//   let user8: HardhatEthersSigner;
//   let nullAddress: string;
//   let ADMIN_ROLE: string;
//   let feeAddresses: string[];

//   // Setting up the fixture before each test
//   beforeEach(async function () {
//     const fixture = await loadFixture(feesFixture);
//     feesContract = fixture.feesContract;
//     feesProxy = fixture.feesProxy;
//     stContract = fixture.stContract;
//     stProxy = fixture.stProxy;
//     owner = fixture.owner;
//     user1 = fixture.user1;
//     user2 = fixture.user2;
//     user3 = fixture.user3;
//     user4 = fixture.user4;
//     user5 = fixture.user5;
//     user6 = fixture.user6;
//     user7 = fixture.user7;
//     user8 = fixture.user8;
//     nullAddress = fixture.nullAddress;
//     ADMIN_ROLE = fixture.ADMIN_ROLE;

//     feeAddresses = [
//       user1.address, // Airdrop
//       user2.address, // Operator
//       user3.address, // StakeTogether
//       user4.address, // Sender
//     ];
//   });

//   // Test to check if pause and unpause functions work properly
//   it("should pause and unpause the contract if the user has admin role", async function () {
//     // Check if the contract is not paused at the beginning
//     expect(await feesContract.paused()).to.equal(false);

//     // User without admin role tries to pause the contract - should fail
//     await expect(connect(feesContract, user1).pause()).to.reverted;

//     // The owner pauses the contract
//     await connect(feesContract, owner).pause();

//     // Check if the contract is paused
//     expect(await feesContract.paused()).to.equal(true);

//     // User without admin role tries to unpause the contract - should fail
//     await expect(connect(feesContract, user1).unpause()).to.reverted;

//     // The owner unpauses the contract
//     await connect(feesContract, owner).unpause();
//     // Check if the contract is not paused
//     expect(await feesContract.paused()).to.equal(false);
//   });

//   it("should upgrade the contract if the user has upgrader role", async function () {
//     expect(await feesContract.version()).to.equal(1n);

//     const MockFees = new MockFees__factory(user1);

//     // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
//     await expect(upgrades.upgradeProxy(feesProxy, MockFees)).to.be.reverted;

//     const MockFeesOwner = new MockFees__factory(owner);

//     // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
//     const upgradedFeesContract = await upgrades.upgradeProxy(
//       feesProxy,
//       MockFeesOwner,
//     );

//     // Upgrade version
//     await upgradedFeesContract.initializeV2();

//     expect(await upgradedFeesContract.version()).to.equal(2n);
//   });

//   it("should correctly set the StakeTogether address", async function () {
//     // User1 tries to set the StakeTogether address to zero address - should fail
//     await expect(connect(feesContract, owner).setStakeTogether(nullAddress)).to
//       .be.reverted;

//     // User1 tries to set the StakeTogether address to their own address - should fail
//     await expect(connect(feesContract, user1).setStakeTogether(user1.address))
//       .to.be.reverted;

//     // Owner sets the StakeTogether address - should succeed
//     await connect(feesContract, owner).setStakeTogether(user1.address);

//     // Verify that the StakeTogether address was correctly set
//     expect(await feesContract.stakeTogether()).to.equal(user1.address);
//   });

//   it("should correctly receive Ether and transfer to StakeTogether via receive", async function () {
//     // Set the StakeTogether address to user1
//     await connect(feesContract, owner).setStakeTogether(user1.address);

//     const initBalance = await ethers.provider.getBalance(user1.address);

//     // User2 sends 1 Ether to the contract's receive function
//     const tx = await user2.sendTransaction({
//       to: feesProxy,
//       value: ethers.parseEther("1.0"),
//     });

//     // Simulate confirmation of the transaction
//     await tx.wait();

//     // Verify that the Ether was correctly transferred to user1 (StakeTogether)
//     const finalBalance = await ethers.provider.getBalance(user1.address);
//     expect(finalBalance).to.equal(initBalance + ethers.parseEther("1.0"));

//     // Verify that the ReceiveEther event was emitted
//     await expect(tx)
//       .to.emit(feesContract, "ReceiveEther")
//       .withArgs(user2.address, ethers.parseEther("1.0"));
//   });

//   it("should return the correct roles from getFeesRoles", async function () {
//     const roles = await feesContract.getFeesRoles();

//     // Check if the returned roles match the expected values
//     expect(roles[0]).to.equal(0); // FeeRole.Airdrop
//     expect(roles[1]).to.equal(1); // FeeRole.Operator
//     expect(roles[2]).to.equal(2); // FeeRole.StakeTogether
//     expect(roles[3]).to.equal(3); // FeeRole.Sender
//   });

//   it("should correctly set the Fee Address", async function () {
//     const role = 0; // FeeRole.StakeAccounts
//     const newAddress = user1.address;

//     // Owner sets the Fee Address for the specified role
//     await connect(feesContract, owner).setFeeAddress(role, newAddress);

//     // Verify that the Fee Address was correctly set
//     expect(await feesContract.getFeeAddress(role)).to.equal(newAddress);
//   });

//   it("should correctly get the Fee Address", async function () {
//     const role = 1; // FeeRole.LockAccounts
//     const newAddress = user2.address;

//     // Owner sets the Fee Address for the specified role
//     await connect(feesContract, owner).setFeeAddress(role, newAddress);

//     // Verify that the Fee Address can be retrieved correctly
//     expect(await feesContract.getFeeAddress(role)).to.equal(newAddress);
//   });

//   it("should correctly get the Fee Addresses for all roles", async function () {
//     // Set Fee Addresses for different roles
//     await connect(feesContract, owner).setFeeAddress(0, user1.address); // FeeRole.Airdrop
//     await connect(feesContract, owner).setFeeAddress(1, user2.address); // FeeRole.Operator
//     await connect(feesContract, owner).setFeeAddress(2, user3.address); // FeeRole.StakeTogether
//     await connect(feesContract, owner).setFeeAddress(3, user4.address); // FeeRole.Sender

//     // Get Fee Addresses for all roles
//     const addresses = await feesContract.getFeeRolesAddresses();

//     // Verify that the Fee Addresses are correct for each role
//     expect(addresses[0]).to.equal(user1.address);
//     expect(addresses[1]).to.equal(user2.address);
//     expect(addresses[2]).to.equal(user3.address);
//     expect(addresses[3]).to.equal(user4.address);
//   });

//   it("should revert if allocations array length is not 4", async function () {
//     const feeType = 0; // Fee.StakeEntry
//     const value = ethers.parseEther("0.01");
//     const mathType = 1; // FeeMath.PERCENTAGE
//     const allocations = [ethers.parseEther("0.1"), ethers.parseEther("0.1")];

//     await expect(
//       connect(feesContract, owner).setFee(
//         feeType,
//         value,
//         mathType,
//         allocations,
//       ),
//     ).to.be.reverted;
//   });

//   it("should revert if the sum of allocations is not 1 ether", async function () {
//     const feeType = 0; // Fee.StakeEntry
//     const value = ethers.parseEther("0.01");
//     const mathType = 1; // FeeMath.PERCENTAGE
//     const allocations = new Array(4).fill(ethers.parseEther("0.2"));

//     await expect(
//       connect(feesContract, owner).setFee(
//         feeType,
//         value,
//         mathType,
//         allocations,
//       ),
//     ).to.be.reverted;
//   });

//   it("should set the fee correctly if the user has admin role and inputs are valid", async function () {
//     const feeType = 0; // Fee.StakeEntry
//     const value = ethers.parseEther("0.01");
//     const mathType = 1; // FeeMath.PERCENTAGE
//     const allocations = new Array(4).fill(ethers.parseEther("0.25"));

//     await connect(feesContract, owner).setFee(
//       feeType,
//       value,
//       mathType,
//       allocations,
//     );

//     const [
//       returnedFeeType,
//       returnedValue,
//       returnedMathType,
//       returnedAllocations,
//     ] = await feesContract.getFee(feeType);

//     expect(returnedFeeType).to.equal(feeType);
//     expect(returnedValue).to.equal(value);
//     expect(returnedMathType).to.equal(mathType);
//     for (let i = 0; i < returnedAllocations.length; i++) {
//       expect(returnedAllocations[i]).to.equal(allocations[i]);
//     }
//   });

//   it("should revert if a user without admin role tries to set the fee", async function () {
//     const feeType = 0; // Fee.StakeEntry
//     const value = ethers.parseEther("0.01");
//     const mathType = 1; // FeeMath.PERCENTAGE
//     const allocations = new Array(8).fill(ethers.parseEther("0.2"));

//     await expect(
//       connect(feesContract, user1).setFee(
//         feeType,
//         value,
//         mathType,
//         allocations,
//       ),
//     ).to.be.reverted;
//   });

//   it("should set the fixed fee correctly if the user has admin role and inputs are valid", async function () {
//     const feeType = 0; // Fee.StakeEntry
//     const value = ethers.parseEther("0.01"); // This will be the fixed fee
//     const mathType = 0; // FeeMath.FIXED
//     const allocations = new Array(4).fill(ethers.parseEther("0.25")); // The allocations still need to sum to 1 ether

//     await connect(feesContract, owner).setFee(
//       feeType,
//       value,
//       mathType,
//       allocations,
//     );

//     const [
//       returnedFeeType,
//       returnedValue,
//       returnedMathType,
//       returnedAllocations,
//     ] = await feesContract.getFee(feeType);

//     expect(returnedFeeType).to.equal(feeType);
//     expect(returnedValue).to.equal(value);
//     expect(returnedMathType).to.equal(mathType);
//     for (let i = 0; i < returnedAllocations.length; i++) {
//       expect(returnedAllocations[i]).to.equal(allocations[i]);
//     }
//   });

//   it("should correctly get all the fees", async function () {
//     // We will set up 6 different fees for testing
//     const feeCount = 4;
//     const fixedValue = ethers.parseEther("0.01"); // This will be the fixed fee
//     const percentageValue = ethers.parseEther("0.02"); // This will be the percentage fee
//     const fixedMathType = 0; // FeeMath.FIXED
//     const percentageMathType = 1; // FeeMath.PERCENTAGE
//     const allocations = new Array(4).fill(ethers.parseEther("0.25"));

//     for (let i = 0; i < feeCount; i++) {
//       if (i % 2 === 0) {
//         // Set fixed fee for even indexed fees
//         await connect(feesContract, owner).setFee(
//           i,
//           fixedValue,
//           fixedMathType,
//           allocations,
//         );
//       } else {
//         // Set percentage fee for odd indexed fees
//         await connect(feesContract, owner).setFee(
//           i,
//           percentageValue,
//           percentageMathType,
//           allocations,
//         );
//       }
//     }

//     const [feeTypes, feeValues, feeMathTypes, feeAllocations] =
//       await feesContract.getFees();

//     expect(feeTypes.length).to.equal(feeCount);
//     expect(feeValues.length).to.equal(feeCount);
//     expect(feeMathTypes.length).to.equal(feeCount);
//     expect(feeAllocations.length).to.equal(feeCount);

//     for (let i = 0; i < feeCount; i++) {
//       expect(feeTypes[i]).to.equal(i);
//       if (i % 2 === 0) {
//         expect(feeValues[i]).to.equal(fixedValue);
//         expect(feeMathTypes[i]).to.equal(fixedMathType);
//       } else {
//         expect(feeValues[i]).to.equal(percentageValue);
//         expect(feeMathTypes[i]).to.equal(percentageMathType);
//       }
//       for (let j = 0; j < feeAllocations[i].length; j++) {
//         expect(feeAllocations[i][j]).to.equal(allocations[j]);
//       }
//     }
//   });

//   it("should correctly estimate the fee percentage", async function () {
//     await connect(feesContract, owner).setStakeTogether(stProxy);

//     for (let i = 0; i < feeAddresses.length; i++) {
//       await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i]);
//     }

//     const feeType = 1; // Set this to the appropriate fee type
//     const amount = ethers.parseEther("1");

//     // Set the fee for the specified type
//     const feeValue = ethers.parseEther("0.01"); // 1%
//     const mathType = 1; // FeeMath.PERCENTAGE
//     const allocations = new Array(4).fill(ethers.parseEther("0.25"));
//     await connect(feesContract, owner).setFee(
//       feeType,
//       feeValue,
//       mathType,
//       allocations,
//     );

//     // Get and log the set fee
//     const fee = await feesContract.getFee(feeType);
//     // console.log('Set fee: ', fee)

//     const [shares, amounts] = await feesContract.estimateFeePercentage(
//       feeType,
//       amount,
//     );

//     // console.log('shares: ', shares)
//     // console.log('amounts: ', amounts)

//     // Check if the shares and amounts are correctly calculated
//     for (let i = 0; i < 3; i++) {
//       const expectedShare = 2500000000000000n; // 0.002% of the amount
//       const expectedAmount = 2500000000000000n; // 0.002 Ether

//       expect(shares[i].toString()).to.equal(expectedShare.toString());
//       expect(amounts[i].toString()).to.equal(expectedAmount.toString());
//     }

//     const expectedShareSender = 992500000000000000n;
//     const expectedAmountSender = 992500000000000000n;

//     expect(shares[3].toString()).to.equal(expectedShareSender.toString());
//     expect(amounts[3].toString()).to.equal(expectedAmountSender.toString());
//   });

//   // it('should correctly distribute the fee percentage with specific allocations', async function () {
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1 // Set this to the appropriate fee type
//   //   const amount = ethers.parseEther('0.99') // The shares amount

//   //   // Set the fee for the specified type
//   //   const feeValue = ethers.parseEther('0.004') // 0.4%
//   //   const mathType = 1 // FeeMath.PERCENTAGE
//   //   const allocations = [
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.4'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.0') // Sender's share allocation set to 0
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   // Get and log the set fee
//   //   const fee = await feesContract.getFee(feeType)
//   //   // console.log('Set fee: ', fee)

//   //   const [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, false)

//   //   // console.log('shares: ', shares)
//   //   // console.log('amounts: ', amounts)

//   //   // Check if the shares and amounts are correctly calculated
//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1') // This is how the contract calculates feeShares

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     // Only calculate for the first 7 roles, as per the contract
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += BigInt(expectedShare)

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   // The remaining shares are allocated to the last role (sender)
//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)
//   // })

//   // it('should correctly distribute the fee percentage with extreme allocations and large amounts', async function () {
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('900000000000000000003') // An extremely large shares amount

//   //   const feeValue = ethers.parseEther('0.5')
//   //   const mathType = 1
//   //   const allocations = [
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.99'), // An extremely large allocation
//   //     ethers.parseEther('0.01'),
//   //     ethers.parseEther('0.0') // Sender's share allocation set to 0
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   const fee = await feesContract.getFee(feeType)
//   //   // console.log('Set fee: ', fee)

//   //   const [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, false)

//   //   // console.log('shares: ', shares)
//   //   // console.log('amounts: ', amounts)

//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1')

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)

//   //   // Calculate and log the total distributed shares
//   //   let totalDistributedShares = 0n
//   //   for (let share of shares) {
//   //     totalDistributedShares += share
//   //   }
//   //   // console.log('Total distributed shares: ', totalDistributedShares)

//   //   // Calculate and log the shares difference
//   //   const sharesDifference = amount - totalDistributedShares
//   //   // console.log('Shares difference: ', sharesDifference)
//   // })

//   // it('should correctly distribute the fee percentage with lower allocations and large amounts', async function () {
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('1'.padEnd(40, '0')) // An extremely large shares amount

//   //   const feeValue = ethers.parseEther('0.5')
//   //   const mathType = 1
//   //   const allocations = [
//   //     ethers.parseEther('0.00000000001'),
//   //     ethers.parseEther('0.00000000001'),
//   //     ethers.parseEther('0.00000000001'),
//   //     ethers.parseEther('0.00000000001'),
//   //     ethers.parseEther('0.00000000001'),
//   //     ethers.parseEther('0.99999999995'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0') // Sender's share allocation set to 0
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   const fee = await feesContract.getFee(feeType)
//   //   // console.log('Set fee: ', fee)

//   //   const [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, false)

//   //   // console.log('shares: ', shares)
//   //   // console.log('amounts: ', amounts)

//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1')

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)

//   //   // Calculate and log the total distributed shares
//   //   let totalDistributedShares = 0n
//   //   for (let share of shares) {
//   //     totalDistributedShares += share
//   //   }
//   //   // console.log('Total distributed shares: ', totalDistributedShares)

//   //   // Calculate and log the shares difference
//   //   const sharesDifference = amount - totalDistributedShares
//   //   // console.log('Shares difference: ', sharesDifference)
//   // })

//   // it('should correctly distribute the fee percentage with big fees', async function () {
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = 10003n // An extremely small shares amount

//   //   const feeValue = ethers.parseEther('0.5')
//   //   const mathType = 1
//   //   const allocations = [
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0')
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   const fee = await feesContract.getFee(feeType)

//   //   const [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, false)

//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1')

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)

//   //   // Calculate and log the total distributed shares
//   //   let totalDistributedShares = 0n
//   //   for (let share of shares) {
//   //     totalDistributedShares += share
//   //   }

//   //   // Calculate and log the shares difference
//   //   const sharesDifference = amount - totalDistributedShares
//   // })

//   // it('should correctly estimate dynamic fee percentage', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('1')
//   //   const feeValue = ethers.parseEther('0.1')

//   //   const mathType = 1
//   //   const allocations = [
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.5'), // An extremely large allocation
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0') // Sender's share allocation set to 0
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   await connect(feesContract, owner).setMaxDynamicFee(ethers.parseEther('0'))

//   //   // Scenario 0: 0 ether in StakeTogether and 0 ether in Liquidity with zero fee
//   //   let [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, true)

//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1')

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)

//   //   // Calculate and log the total distributed shares
//   //   let totalDistributedShares = 0n
//   //   for (let share of shares) {
//   //     totalDistributedShares += share
//   //   }
//   //   // console.log('Total distributed shares: ', totalDistributedShares)

//   //   // Calculate and log the shares difference
//   //   const sharesDifference = amount - totalDistributedShares
//   //   // console.log('Shares difference: ', sharesDifference)

//   //   expect(sharesDifference).to.equal(0n) // Expect that the difference in shares is 0

//   //   await connect(feesContract, owner).setMaxDynamicFee(ethers.parseEther('1'))

//   //   /** LIBRA MECHANISM */

//   //   // Scenario 1: 0 ether in StakeTogether and 100 ether in Liquidity

//   //   await owner.sendTransaction({ to: liquidityProxy, value: ethers.parseEther('100') })

//   //   let [shares2, amounts2] = await feesContract.estimateFeePercentage(feeType, amount, true)

//   //   let baseFee2 = feeValue

//   //   let totalAllocatedShares2 = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare2 = (baseFee2 * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares2 += expectedShare2

//   //     const expectedAmount2 = amounts2[i]

//   //     expect(shares2[i]).to.equal(expectedShare2)
//   //     expect(amounts2[i]).to.equal(expectedAmount2)
//   //   }

//   //   const expectedShareSender2 = amount - totalAllocatedShares2
//   //   const expectedAmountSender2 = amounts2[7]

//   //   expect(shares2[7]).to.equal(expectedShareSender2)
//   //   expect(amounts2[7]).to.equal(expectedAmountSender2)

//   //   // Scenario 2: 100 ether in StakeTogether and 100 ether in Liquidity

//   //   await owner.sendTransaction({ to: stProxy, value: ethers.parseEther('100') })

//   //   let [shares3, amounts3] = await feesContract.estimateFeePercentage(feeType, amount, true)

//   //   // The fee should now be double the base fee as per your dynamic fee calculation function
//   //   let dynamicFee3 = baseFee2 * 2n // Calculating expected dynamicFee manually

//   //   let totalAllocatedShares3 = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare3 = (dynamicFee3 * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares3 += expectedShare3

//   //     const expectedAmount3 = amounts3[i]

//   //     expect(shares3[i]).to.equal(expectedShare3)
//   //     expect(amounts3[i]).to.equal(expectedAmount3)
//   //   }

//   //   const expectedShareSender3 = amount - totalAllocatedShares3
//   //   const expectedAmountSender3 = amounts3[7]

//   //   expect(shares3[7]).to.equal(expectedShareSender3)
//   //   expect(amounts3[7]).to.equal(expectedAmountSender3)
//   // })

//   // it('should correctly estimate dynamic fee percentage libra 100-0', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('1')
//   //   const feeValue = ethers.parseEther('0.1')

//   //   const mathType = 1
//   //   const allocations = [
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.5'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0')
//   //   ]
//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations)

//   //   await connect(feesContract, owner).setMaxDynamicFee(ethers.parseEther('0'))

//   //   let [shares, amounts] = await feesContract.estimateFeePercentage(feeType, amount, true)

//   //   const feeShares = (amount * feeValue) / ethers.parseEther('1')

//   //   let totalAllocatedShares = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeShares * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare

//   //     const expectedAmount = amounts[i]

//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(expectedAmount)
//   //   }

//   //   const expectedShareSender = amount - totalAllocatedShares
//   //   const expectedAmountSender = amounts[7]

//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(expectedAmountSender)

//   //   let totalDistributedShares = 0n
//   //   for (let share of shares) {
//   //     totalDistributedShares += share
//   //   }

//   //   const sharesDifference = amount - totalDistributedShares

//   //   expect(sharesDifference).to.equal(0n)

//   //   await connect(feesContract, owner).setMaxDynamicFee(ethers.parseEther('1'))

//   //   let [shares3, amounts3] = await feesContract.estimateFeePercentage(feeType, amount, true)

//   //   let dynamicFee3 = feeValue * 2n // Calculating expected dynamicFee manually

//   //   let totalAllocatedShares3 = 0n

//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare3 = (dynamicFee3 * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares3 += expectedShare3

//   //     const expectedAmount3 = amounts3[i]

//   //     expect(shares3[i]).to.equal(expectedShare3)
//   //     expect(amounts3[i]).to.equal(expectedAmount3)
//   //   }

//   //   const expectedShareSender3 = amount - totalAllocatedShares3
//   //   const expectedAmountSender3 = amounts3[7]

//   //   expect(shares3[7]).to.equal(expectedShareSender3)
//   //   expect(amounts3[7]).to.equal(expectedAmountSender3)
//   // })

//   // it('should revert if fee is not of type percentage', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('1')
//   //   const feeValue = ethers.parseEther('0.1')

//   //   // Set the mathType to a value different from percentage (assuming 0 is not percentage)
//   //   const allocations = [
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.5'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0')
//   //   ]

//   //   await connect(feesContract, owner).setFee(feeType, feeValue, 0, allocations) // 0 is not 'percentage'

//   //   // Call estimateFee() and expect it to revert
//   //   await expect(feesContract.estimateFeePercentage(feeType, amount, true)).to.be.reverted
//   // })

//   // it('should revert if any fee address is zero address', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   const feeType = 1
//   //   const amount = ethers.parseEther('1')
//   //   const feeValue = ethers.parseEther('0.1')

//   //   // Set the mathType to percentage and allocations
//   //   const allocations = [
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.1'),
//   //     ethers.parseEther('0.5'),
//   //     ethers.parseEther('0.0'),
//   //     ethers.parseEther('0.0')
//   //   ]

//   //   await connect(feesContract, owner).setFee(feeType, feeValue, 1, allocations) // 1 is 'percentage'

//   //   // Set one of the fee addresses to the zero address
//   //   await connect(feesContract, owner).setFeeAddress(0, nullAddress)

//   //   // Call estimateFee() and expect it to revert
//   //   await expect(feesContract.estimateFee(feeType, amount, true)).to.be.revertedWith('ZERO_ADDRESS')
//   // })

//   // it('should return correct shares and amounts when fee type is FIXED', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const feeValue = ethers.parseEther('1') // 1 ether for simplicity

//   //   const mathType = 0 // FIXED
//   //   const allocations = [
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.250'),
//   //     ethers.parseEther('0')
//   //   ]

//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations) // Set fee as FIXED

//   //   // Call estimateFeeFixed() and expect it to be successful
//   //   let [shares, amounts] = await feesContract.estimateFeeFixed(feeType)

//   //   // console.log('shares: ', shares)
//   //   // console.log('amounts: ', amounts)

//   //   let totalAllocatedShares = 0n
//   //   for (let i = 0; i < 7; i++) {
//   //     const expectedShare = (feeValue * allocations[i]) / ethers.parseEther('1')
//   //     totalAllocatedShares += expectedShare
//   //     expect(shares[i]).to.equal(expectedShare)
//   //     expect(amounts[i]).to.equal(amounts[i]) // Because amounts[i] should equal to expectedAmount in the mock contract
//   //   }

//   //   const expectedShareSender = feeValue - totalAllocatedShares
//   //   expect(shares[7]).to.equal(expectedShareSender)
//   //   expect(amounts[7]).to.equal(amounts[7]) // Because amounts[7] should equal to expectedAmount in the mock contract
//   // })

//   // it('should revert if fee type is not FIXED', async function () {
//   //   // Setting the StakeTogether
//   //   await connect(feesContract, owner).setStakeTogether(stProxy)
//   //   await connect(feesContract, owner).setLiquidity(liquidityProxy)

//   //   for (let i = 0; i < feeAddresses.length; i++) {
//   //     await connect(feesContract, owner).setFeeAddress(i, feeAddresses[i])
//   //   }

//   //   const feeType = 1
//   //   const feeValue = ethers.parseEther('1') // 1 ether for simplicity

//   //   const mathType = 1 // PERCENTAGE
//   //   const allocations = [
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2'),
//   //     ethers.parseEther('0.2')
//   //   ]

//   //   await connect(feesContract, owner).setFee(feeType, feeValue, mathType, allocations) // Set fee as PERCENTAGE

//   //   // Call estimateFeeFixed() and expect it to revert
//   //   await expect(feesContract.estimateFeeFixed(feeType)).to.be.reverted
//   // })
// });
