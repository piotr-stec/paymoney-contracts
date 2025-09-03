const hre = require("hardhat");

async function main() {
  console.log("Deploying Visoft Token contract...");

  // Get the deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy Visoft contract with deployer as initial owner
  const Visoft = await hre.ethers.getContractFactory("Visoft");
  const visoftToken = await Visoft.deploy(deployer.address);
  
  await visoftToken.waitForDeployment();

  console.log(`Visoft Token deployed to: ${visoftToken.target}`);
  console.log(`Owner: ${deployer.address}`);

  // Return deployed addresses for use in other scripts
  return {
    visoftToken: visoftToken.target,
    owner: deployer.address
  };
}

// Allow script to be called from other scripts
if (require.main === module) {
  main()
    .then((addresses) => {
      console.log("\n=== Deployment Summary ===");
      console.log("Visoft Token:", addresses.visoftToken);
      console.log("Owner:", addresses.owner);
      process.exit(0);
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}

module.exports = main;