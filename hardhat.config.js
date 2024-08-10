require("@nomiclabs/hardhat-waffle")
require("@nomicfoundation/hardhat-verify")
require("hardhat-deploy")
require("solidity-coverage")
require("hardhat-gas-reporter")
require("hardhat-contract-sizer")
require("dotenv").config()

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const SEPOLIA_RPC_URL = process.env.NETWORK_URL

const PRIVATE_KEY = process.env.PRIVATE_KEY
// Your API key for Etherscan, obtain one at https://etherscan.io/
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            // // If you want to do some forking, uncomment this
            // forking: {
            //   url: MAINNET_RPC_URL
            // }
            chainId: 31337,
        },
        localhost: {
            chainId: 31337,
        },
        sepolia: {
            url: SEPOLIA_RPC_URL,
            accounts: [PRIVATE_KEY],
            saveDeployments: true,
            chainId: 11155111,
        },
    },
    etherscan: {
        // yarn hardhat verify --network <NETWORK> <CONTRACT_ADDRESS> <CONSTRUCTOR_PARAMETERS>
        apiKey: {
            sepolia: ETHERSCAN_API_KEY,
        },
        customChains: [
            {
                network: "goerli",
                chainId: 5,
                urls: {
                    apiURL: "https://api-goerli.etherscan.io/api",
                    browserURL: "https://goerli.etherscan.io",
                },
            },
        ],
    },
    gasReporter: {
        enabled: false,
        currency: "USD",
        outputFile: "gas-report.txt",
        noColors: true,
        // coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    },
    contractSizer: {
        runOnCompile: false,
        only: ["Raffle"],
    },
    namedAccounts: {
        deployer: {
            default: 0, // here this will by default take the first account as deployer
            1: 0, // similarly on mainnet it will take the first account as deployer. Note though that depending on how hardhat network are configured, the account 0 on one network can be different than on another
        },
        player: {
            default: 1,
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.19",
            },
            {
                version: "0.4.24",
            },
        ],
    },
    mocha: {
        timeout: 500000, // 500 seconds max for running tests
    },
}
