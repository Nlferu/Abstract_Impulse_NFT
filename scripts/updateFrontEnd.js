const { ethers } = require("hardhat")
const frontEndContractsFile = "../no-patrick-code/constants/networkMapping.json"
const frontEndAbiLocation = "../no-patrick-code/constants/"
const fs = require("fs")

async function updateFrontEnd() {
    if (process.env.UPDATE_FRONT_END) {
        console.log("Updating front end...")
        await updateContractAddresses()
        await updateAbi()
    }
}

async function updateAbi() {
    const abstractImpulseNft = await ethers.getContract("AbstractImpulseNFT")
    fs.writeFileSync(`${frontEndAbiLocation}AbstractImpulseNFT.json`, abstractImpulseNft.interface.format(ethers.utils.FormatTypes.json))
}

async function updateContractAddresses() {
    const abstractImpulseNft = await ethers.getContract("AbstractImpulseNFT")
    const chainId = network.config.chainId.toString()
    const contractAddresses = JSON.parse(fs.readFileSync(frontEndContractsFile, "utf8"))
    if (chainId in contractAddresses) {
        if (!contractAddresses[chainId]["AbstractImpulseNFT"].includes(abstractImpulseNft.address)) {
            contractAddresses[chainId]["AbstractImpulseNFT"].push(abstractImpulseNft.address)
        }
    } else {
        contractAddresses[chainId] = { AbstractImpulseNFT: [abstractImpulseNft.address] }
    }
    fs.writeFileSync(frontEndContractsFile, JSON.stringify(contractAddresses))
}

updateFrontEnd()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })