const hre = require("hardhat");

async function main() {
    console.log("=== Deploying TLSN Transaction Verifier ===");

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying with account:", deployer.address);

    // Get account balance
    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Account balance:", hre.ethers.formatEther(balance), "ETH");

    try {
        // Deploy HonkVerifierTransactionTlsn
        console.log("\nDeploying HonkVerifierTransactionTlsn...");
        
        const HonkVerifierTransactionTlsn = await hre.ethers.getContractFactory("HonkVerifierTransactionTlsn");
        
        console.log("Deploying contract...");
        const verifier = await HonkVerifierTransactionTlsn.deploy();
        
        console.log("Waiting for deployment confirmation...");
        await verifier.waitForDeployment();
        
        const verifierAddress = await verifier.getAddress();
        console.log(" HonkVerifierTransactionTlsn deployed to:", verifierAddress);


    } catch (error) {
        console.error("\nL Deployment failed:");
        console.error("Error:", error.message);
        
        if (error.code === 'INSUFFICIENT_FUNDS') {
            console.log("\n=� Solution: Add more ETH to your account");
        } else if (error.message.includes('contract not found')) {
            console.log("\n=� Solution: Make sure the contract compiles successfully");
            console.log("   Run: npx hardhat compile");
        }
        
        process.exit(1);
    }
}

main()
    .then(() => {
        console.log("\n Deployment completed successfully");
        process.exit(0);
    })
    .catch((error) => {
        console.error("\nL Deployment failed:", error);
        process.exit(1);
    });