import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import dotenv from "dotenv";
import { upgrades } from "hardhat";
import {
  MockRouter__factory,
  MockStakeTogether,
  Router,
} from "../../typechain";
import connect from "../utils/connect";
import { routerFixture } from "./Router.fixture";

dotenv.config();

describe("Router", function () {
  let router: Router;
  let routerProxy: string;
  let stakeTogether: MockStakeTogether;
  let stakeTogetherProxy: string;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let user3: HardhatEthersSigner;
  let user4: HardhatEthersSigner;
  let user5: HardhatEthersSigner;
  let user6: HardhatEthersSigner;
  let user7: HardhatEthersSigner;
  let user8: HardhatEthersSigner;
  let nullAddress: string;
  let ADMIN_ROLE: string;

  // Setting up the fixture before each test
  beforeEach(async function () {
    const fixture = await loadFixture(routerFixture);
    router = fixture.router;
    routerProxy = fixture.routerProxy;
    stakeTogether = fixture.stakeTogether;
    stakeTogetherProxy = fixture.stakeTogetherProxy;
    owner = fixture.owner;
    user1 = fixture.user1;
    user2 = fixture.user2;
    user3 = fixture.user3;
    user4 = fixture.user4;
    user5 = fixture.user5;
    user6 = fixture.user6;
    user7 = fixture.user7;
    user8 = fixture.user8;
    nullAddress = fixture.nullAddress;
    ADMIN_ROLE = fixture.ADMIN_ROLE;
  });

  describe("Upgrade", () => {
    // Test to check if pause and unpause functions work properly
    it("should pause and unpause the contract if the user has admin role", async function () {
      // Check if the contract is not paused at the beginning
      expect(await router.paused()).to.equal(false);

      // User without admin role tries to pause the contract - should fail
      await expect(connect(router, user1).pause()).to.reverted;

      // The owner pauses the contract
      await connect(router, owner).pause();

      // Check if the contract is paused
      expect(await router.paused()).to.equal(true);

      // User without admin role tries to unpause the contract - should fail
      await expect(connect(router, user1).unpause()).to.reverted;

      // The owner unpauses the contract
      await connect(router, owner).unpause();
      // Check if the contract is not paused
      expect(await router.paused()).to.equal(false);
    });

    it("should upgrade the contract if the user has upgrader role", async function () {
      expect(await router.version()).to.equal(1n);

      const MockRouter = new MockRouter__factory(user1);

      // A user without the UPGRADER_ROLE tries to upgrade the contract - should fail
      await expect(upgrades.upgradeProxy(routerProxy, MockRouter)).to.be
        .reverted;

      const MockRouterOwner = new MockRouter__factory(owner);

      // The owner (who has the UPGRADER_ROLE) upgrades the contract - should succeed
      const upgradedContract = await upgrades.upgradeProxy(
        routerProxy,
        MockRouterOwner,
      );

      // Upgrade version
      await upgradedContract.initializeV2();

      expect(await upgradedContract.version()).to.equal(2n);
    });
  });

  // it("should correctly set the StakeTogether address", async function () {
  //   // User1 tries to set the StakeTogether address to zero address - should fail
  //   await expect(connect(router, owner).setStakeTogether(nullAddress)).to.be
  //     .reverted;

  //   // User1 tries to set the StakeTogether address to their own address - should fail
  //   await expect(connect(router, user1).setStakeTogether(user1.address)).to.be
  //     .reverted;

  //   // Owner sets the StakeTogether address - should succeed
  //   await connect(router, owner).setStakeTogether(user1.address);

  //   // Verify that the StakeTogether address was correctly set
  //   expect(await router.stakeTogether()).to.equal(user1.address);
  // });
});
