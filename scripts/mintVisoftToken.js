const hre = require("hardhat");

async function main() {
  // Configuration - update these values as needed
  const TOKEN_ADDRESS = "0x4CB849A39D4201ff65C479c09B17Bbe12f9c1d67"; // Replace with deployed token address
  const MINT_TO_ADDRESS = "0xD82c390E4D58BF25F7Af94A6Bee4fCff64936c72"; // Replace with recipient address
  const MINT_AMOUNT = hre.ethers.parseEther("1000"); // Amount to mint (1000 tokens)

  console.log("Minting Visoft tokens...");
  console.log("Token Address:", TOKEN_ADDRESS);
  console.log("Mint To:", MINT_TO_ADDRESS);
  console.log("Amount:", hre.ethers.formatEther(MINT_AMOUNT), "VST");

  // Get the signer (must be the owner)
  const [signer] = await hre.ethers.getSigners();
  console.log("Minting with account:", signer.address);

  // Get the contract instance
  const visoftToken = await hre.ethers.getContractAt("Visoft", TOKEN_ADDRESS);

  // Check if signer is the owner
  const owner = await visoftToken.owner();
  if (signer.address.toLowerCase() !== owner.toLowerCase()) {
    throw new Error(`Only owner can mint. Owner: ${owner}, Signer: ${signer.address}`);
  }

  // Mint tokens
  console.log("Executing mint transaction...");
  const tx = await visoftToken.mint(MINT_TO_ADDRESS, MINT_AMOUNT);
  console.log("Transaction hash:", tx.hash);
  
  // Wait for confirmation
  await tx.wait();
  console.log("Mint completed successfully!");

  // Check new balance
  const balance = await visoftToken.balanceOf(MINT_TO_ADDRESS);
  console.log("New balance:", hre.ethers.formatEther(balance), "VST");
}

// Allow script to be called from other scripts
if (require.main === module) {
  main()
    .then(() => {
      console.log("\n=== Mint Summary ===");
      console.log("Tokens minted successfully");
      process.exit(0);
    })
    .catch((error) => {
      console.error("Error:", error.message);
      process.exitCode = 1;
    });
}

module.exports = main;