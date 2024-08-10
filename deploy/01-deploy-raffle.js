const { network, ethers } = require("hardhat")
const {
    networkConfig,
    developmentChains,
    VERIFICATION_BLOCK_CONFIRMATIONS,
} = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

const FUND_AMOUNT = ethers.utils.parseEther("1") // 1 Ether, or 1e18 (10^18) Wei

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const chainId = network.config.chainId
    let vrfCoordinatorV2_5Address, subscriptionId, vrfCoordinatorV2_5Mock

    if (chainId == 31337) {
        // create VRFV2 Subscription
        vrfCoordinatorV2_5Mock = await ethers.getContract("VRFCoordinatorV2_5Mock")
        vrfCoordinatorV2_5Address = vrfCoordinatorV2_5Mock.address
        const transactionResponse = await vrfCoordinatorV2_5Mock.createSubscription()
        const transactionReceipt = await transactionResponse.wait()
        subscriptionId = transactionReceipt.events[0].args.subId
        // Fund the subscription
        // Our mock makes it so we don't actually have to worry about sending fund
        await vrfCoordinatorV2_5Mock.fundSubscription(subscriptionId, FUND_AMOUNT)
    } else {
        vrfCoordinatorV2_5Address = networkConfig[chainId]["vrfCoordinatorV2_5"]
        subscriptionId = networkConfig[chainId]["subscriptionId"]
    }
    const waitBlockConfirmations = developmentChains.includes(network.name)
        ? 1
        : VERIFICATION_BLOCK_CONFIRMATIONS

    log("----------------------------------------------------")
    const args = [
        networkConfig[chainId]["raffleEntranceFee"],
        subscriptionId,
        networkConfig[chainId]["keyHash"],
        vrfCoordinatorV2_5Address,
        networkConfig[chainId]["callbackGasLimit"],
        networkConfig[chainId]["keepersUpdateInterval"],
    ]
    const raffle = await deploy("Raffle", {
        from: deployer,
        args: args,
        log: true,
        waitConfirmations: waitBlockConfirmations,
    })

    // Ensure the Raffle contract is a valid consumer of the VRFCoordinatorV2Mock contract.
    if (developmentChains.includes(network.name)) {
        await vrfCoordinatorV2_5Mock.addConsumer(subscriptionId, raffle.address)
    }

    // Verify the deployment
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        log("Verifying...")
        await verify(raffle.address, arguments)
    }

    log("Enter lottery with command:")
    const networkName = network.name == "hardhat" ? "localhost" : network.name
    log(`yarn hardhat run scripts/enterRaffle.js --network ${networkName}`)
    log("----------------------------------------------------")
}

module.exports.tags = ["all", "raffle"]
