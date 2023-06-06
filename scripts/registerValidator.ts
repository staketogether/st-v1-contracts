// import * as dotenv from 'dotenv'
// import { ethers } from 'hardhat'
// import { checkVariables } from '../test/utils/env'
// import { IERC20__factory, ISSVNetwork__factory } from '../typechain'

// dotenv.config()

// export async function executeTxs() {
//   checkVariables()
//   await registerValidator()
// }

// async function registerValidator() {
//   const [owner] = await ethers.getSigners()

//   const SSVNetwork = ISSVNetwork__factory.connect(process.env.GOERLI_SSV_NETWORK_ADDRESS as string, owner)
//   const SSVToken = IERC20__factory.connect(process.env.GOERLI_SSV_TOKEN_ADDRESS as string, owner)

//   const ethValidator = {
//     deposit: {
//       pubkey:
//         'ad1c77784ae2c6ac46ca953289f8fd702920d12d385f9491e0907d6e98e9c0fdf1180e75dcfec7bb6dfb9ed6251c68ac',
//       signature:
//         '81626e0b0268eec5279629a6551d72e3de33ea64b998851366b597ec6b5ea671c75873e5a7821bf4f684f1e48b4b3b600b43b25576b0cc2a09a64f3be6ebb043ff99b391f32a69a46387e08f3f6a9244034a5658e9797ccc0776e78f7acda1d9',
//       deposit_data_root: 'c417468ccfab51238034dbf4f6d89b471bc12860f33a0f611f2692f010ebcf0d'
//     },
//     ssvNetwork: {
//       publicKey:
//         '0x8c4420559d2b5ec5020960ba71acfef35a4537b620f1007fd6378d8a6f45d58abc076ef0785029f7aa40951859bedf46',
//       operatorIds: [1, 2, 3, 4],
//       shares:
//         '0x0182845319bb08b07ade93e120d745e2d39cdc5a66034fc4fa35cd4d2c6b5a3c66cf4b0e417cf7a5668406d1b2d1b36feb5c8f8ed793262f6e47b414a42ddb7824523ea9f2f25bb094f6649434e0953f9d897054664d8ba98728040af8d1441c58e187d91508ca6db5bbad9ea1fa32fd0954e448f456d5f6cf1c597a5796dc0092d551c4b2a02454550ad5214891b326c569b83728f83ca4be1dbad88a50ea5923ddaf2562007a6729de07627ae59d4d58c2dbe63fcae3966df3d45aeedf7d6152f96a3f4128aaf8adff29dfff01cdf2f2f0f9616d9e1223811e2691da84000b6d0f33ceb027b11782074d452fc9e864d41bce535d36d523fd7d94d8a9a8360ae04065665754bc13b4ac12e7a3f6573e3d9d0072520cc1a270fbb47ca1f9f68eb764c0cfe5789b8a803a47c1057bf61aa94f4ded80e004b73a924f11c95d96701e291dd3d4160dae4bc255024af8cbfcea63e1d963321364c1ece6e8c3467c7d177e1e969eab32ce7cd1800c500c224cac22ef5125e52c7a9b82a6c29f0c4ffef588e8b671229f37588bef91895996107b8eef7abb096b44a9feececd808ecb5fe5ab0b039e4cc591e531ded375ad519d767320d22ce46c8c98b064afce28997615d2da1c29abb51f88771f1602f3275091487595500e94c80856fde44fb0d79f76afe7ab5fca3a825ff2b5d44b78dc42e7227c73736e909ecfdde6ec4a0299801e7247015fb300a587f952c4624512cf9417c4ffbbda8db9d472a6c1043d46cb0193a03fb8c5518db93e90c958739a495484c1761fa3aa47c2bc1b5d48e3c2905234a9d5873f0444d6066dd05c15aa3a409835f786173280243c6357b4bfec4a929daf46cfb31c729d1b1cfc6047b7741668472bbde30d845936c15eb37e2f7532e4952572617b2f3f29513f7d63d55d1645d4c627c16ca3e9e097d1e07c9bad78518e27dd9b695e430df68729904c0f4157164ff38b5b3012cf589be0468b4d0a18f38f3d75d0fd96286953ef7875e7ea5284435d12da37646f57dd1a4e57cf9242e85025ee7f1f5ba05b38dd87f1d5cd3769e6a41d8441d7a4b3a03c710ebf6c455db37df72e1590d27091e7972495756e2eb94731acb2407d9d9f66ad3155bd0dc9c7e84534817a1e841084eedc645fcf509e567a3cfe12f01390d65c28000f21c14a6507248d9e96cc2773abb79d106356367aba5f34b58b4dec4e7790e1fdf843b440391b976f7c929c229787e0a1da78b58f40c9ac149725655f7cdc1d402ea14ce9d62c62c19e3db2e98f5d891b6ddda7e0e78962b5c1318a34d15d44cc3bd0414deb3447e0c4fd83051f01615194c7274abf2a1b7d3ae66543275e14e62b84e3637570e9061c0f120f653f89a733f06af38eff088b0924b60cc4e7fe3c50d6ebdd64cad28eb07d090f65f216f5cb33104507b299e7b74db8b62ccdba35210838f7dbdcfd1d7ccf27fea4f8ee850e6864d664839d4259e98af587728c8267b971db0f1890be0a23647e89ef0c31841a5dfa5653cd90a817f3ddb74b18924c403d0fd9c95cdb031f51406526507ec8a10cfb37b801218c9863b17a1ab6ff986297d25e586dc841db2ddedb1fed40a52be63bece2e9a57211d59f831ffd8f80a3f612029e5a01baf7599cd39ccc931c34579cf937350473e7d4df6de771b3440a23ce2c25f92433b13a69b9326e940adbd0ad2fe3fd5c203cf68401b65105b',
//       amount:
//         "Amount of SSV tokens to be deposited to your validator's cluster balance (mandatory only for 1st validator in a cluster)",
//       cluster:
//         "The latest cluster snapshot data, obtained using the cluster-scanner tool. If this is the cluster's 1st validator then use - {0,0,0,0,true}"
//     }
//   }

//   const amount = ethers.parseEther('10')

//   const approveSSV = await SSVToken.approve(await SSVNetwork.getAddress(), amount)

//   await new Promise(resolve => setTimeout(resolve, 5000))

//   console.log('TX SSV Approve', approveSSV.hash)

//   try {
//     const registerTX = await SSVNetwork.registerValidator(
//       ethValidator.ssvNetwork.publicKey,
//       ethValidator.ssvNetwork.operatorIds,
//       ethValidator.ssvNetwork.shares,
//       amount,
//       {
//         validatorCount: 0,
//         networkFeeIndex: 0,
//         index: 0,
//         balance: 0,
//         active: true
//       }
//     )

//     console.log('TX Register STValidator', registerTX.hash)
//   } catch (error) {
//     console.error(error)
//   }
// }

// executeTxs().catch(error => {
//   console.error(error)
//   process.exitCode = 1
// })
