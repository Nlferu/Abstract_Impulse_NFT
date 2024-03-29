const { ethers, network } = require("hardhat")
const { developmentChains } = require("../helper-hardhat-config")
const prompt = require("prompt-sync")()

let tokenURI = prompt("TokenURI of new NFT: ")

async function mintNFT() {
    const abstractImpulseNFT = await ethers.getContract("AbstractImpulseNFT")

    console.log(`Working With AbstractImpulseNFT Contract: ${abstractImpulseNFT.address} Owner: ${await abstractImpulseNFT.owner()}`)

    const responseTx = await abstractImpulseNFT.mintNFT(tokenURI)
    const receiptTx = await responseTx.wait()
    const minter = receiptTx.events[1].args.minter
    const uri = receiptTx.events[2].args.uri
    const token = receiptTx.events[2].args.tokenId

    console.log(`NFT Minted!`)
    console.log(`Minter: ${minter}`)
    console.log(`TokenURI: ${uri} TokenId: ${token}`)
}

if (!developmentChains.includes(network.name)) {
    mintNFT()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error)
            process.exit(1)
        })
} else {
    console.log("This script is allowed only for Goerli, Sepolia or Mainnet")
}
