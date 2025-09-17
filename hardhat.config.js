require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    sepolia: {
      url: "https://eth-sepolia.g.alchemy.com/v2/rNDiYBb9E5C7e3FwLaObfcIQfcLb8IlN",
      accounts: ["35809c729706777acca66b73c044673fc1f97c674770533906439292fc89d44b"],
      chainId: 11155111,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: ["35809c729706777acca66b73c044673fc1f97c674770533906439292fc89d44b"],
      chainId: 31337,
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.21",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
      {
        version: "0.8.27",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      }
    ]
  },
};