const hre = require("hardhat");

const PRIVACY_POOL_ADDRESS = "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707";

async function main() {
    console.log("=== Reading PrivacyPool Events ===");

    const privacyPool = await hre.ethers.getContractAt("PrivacyPool", PRIVACY_POOL_ADDRESS);
    console.log("Reading events from:", PRIVACY_POOL_ADDRESS);

    try {
        // Get current block number
        const currentBlock = await hre.ethers.provider.getBlockNumber();
        console.log("Current block:", currentBlock);
        
        // Define block range (last 1000 blocks or from deployment)
        const fromBlock = Math.max(0, currentBlock - 1000);
        const toBlock = currentBlock;
        
        console.log(`Scanning blocks ${fromBlock} to ${toBlock}...\n`);

        // Read all events from the contract
        console.log("=== ALL EVENTS ===");
        const allEvents = await privacyPool.queryFilter("*", fromBlock, toBlock);
        
        if (allEvents.length === 0) {
            console.log("No events found in the specified block range.");
        } else {
            console.log(`Found ${allEvents.length} total events:\n`);
            
            allEvents.forEach((event, index) => {
                console.log(`Event ${index + 1}:`);
                console.log(`- Name: ${event.eventName || 'Unknown'}`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log(`- Transaction Hash: ${event.transactionHash}`);
                console.log(`- Args:`, event.args);
                console.log('---');
            });
        }

        // Read specific events
        console.log("\n=== DEPOSIT EVENTS ===");
        const depositEvents = await privacyPool.queryFilter(
            privacyPool.filters.Deposit(),
            fromBlock,
            toBlock
        );
        
        if (depositEvents.length > 0) {
            depositEvents.forEach((event, index) => {
                console.log(`Deposit ${index + 1}:`);
                console.log(`- Secret Nullifier Hash: ${event.args.secretNullifierHash}`);
                console.log(`- Amount: ${hre.ethers.formatUnits(event.args.amount, 6)} tokens`); // 6 decimals
                console.log(`- Token: ${event.args.token}`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log(`- TX Hash: ${event.transactionHash}`);
                console.log('---');
            });
        } else {
            console.log("No Deposit events found.");
        }

        console.log("\n=== OFFER CREATED EVENTS ===");
        const offerEvents = await privacyPool.queryFilter(
            privacyPool.filters.OfferCreated(),
            fromBlock,
            toBlock
        );
        
        if (offerEvents.length > 0) {
            offerEvents.forEach((event, index) => {
                console.log(`Offer ${index + 1}:`);
                console.log(`- Secret Hash: ${event.args.secretHash}`);
                console.log(`- Offer Type: ${event.args.offerType}`);
                console.log(`- Crypto Amount: ${hre.ethers.formatUnits(event.args.cryptoAmount, 6)} tokens`);
                console.log(`- Fiat Amount: ${event.args.fiatAmount} cents`);
                console.log(`- Currency: ${event.args.currency}`);
                console.log(`- Token Address: ${event.args.tokenAddress}`);
                console.log(`- RevTag: ${event.args.revTag}`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log(`- TX Hash: ${event.transactionHash}`);
                console.log('---');
            });
        } else {
            console.log("No OfferCreated events found.");
        }

        console.log("\n=== TRANSACTION CREATED EVENTS ===");
        const transactionEvents = await privacyPool.queryFilter(
            privacyPool.filters.TransactionCreated(),
            fromBlock,
            toBlock
        );
        
        if (transactionEvents.length > 0) {
            transactionEvents.forEach((event, index) => {
                console.log(`Transaction ${index + 1}:`);
                console.log(`- Transaction ID: ${event.args.transactionId}`);
                console.log(`- Offer Secret Hash: ${event.args.offerSecretHash}`);
                console.log(`- Offer Type: ${event.args.offerType}`);
                console.log(`- Crypto Amount: ${hre.ethers.formatUnits(event.args.cryptoAmount, 6)} tokens`);
                console.log(`- Fiat Amount: ${event.args.fiatAmount} cents`);
                console.log(`- Title: ${event.args.title}`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log(`- TX Hash: ${event.transactionHash}`);
                console.log('---');
            });
        } else {
            console.log("No TransactionCreated events found.");
        }

        console.log("\n=== TRANSACTION VERIFIED EVENTS ===");
        const verifiedEvents = await privacyPool.queryFilter(
            privacyPool.filters.TransactionVerified(),
            fromBlock,
            toBlock
        );
        
        if (verifiedEvents.length > 0) {
            verifiedEvents.forEach((event, index) => {
                console.log(`Verified Transaction ${index + 1}:`);
                console.log(`- Transaction ID: ${event.args.transactionId}`);
                console.log(`- Comment: ${event.args.comment}`);
                console.log(`- Final Fiat Amount: ${event.args.finalFiatAmount} cents`);
                console.log(`- Crypto To Send: ${hre.ethers.formatUnits(event.args.cryptoToSend, 6)} tokens`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log(`- TX Hash: ${event.transactionHash}`);
                console.log('---');
            });
        } else {
            console.log("No TransactionVerified events found.");
        }

        console.log("\n=== LEAF ADDED EVENTS ===");
        const leafEvents = await privacyPool.queryFilter(
            privacyPool.filters.LeafAdded(),
            fromBlock,
            toBlock
        );
        
        if (leafEvents.length > 0) {
            console.log(`Found ${leafEvents.length} LeafAdded events (showing first 5):`);
            leafEvents.slice(0, 5).forEach((event, index) => {
                console.log(`Leaf ${index + 1}:`);
                console.log(`- Caller: ${event.args.caller}`);
                console.log(`- Commitment: ${event.args.commitment}`);
                console.log(`- New Root: ${event.args.newRoot}`);
                console.log(`- Block: ${event.blockNumber}`);
                console.log('---');
            });
            
            if (leafEvents.length > 5) {
                console.log(`... and ${leafEvents.length - 5} more LeafAdded events`);
            }
        } else {
            console.log("No LeafAdded events found.");
        }

        // Summary
        console.log("\n=== SUMMARY ===");
        console.log(`📊 Total Events: ${allEvents.length}`);
        console.log(`💰 Deposits: ${depositEvents.length}`);
        console.log(`🏪 Offers Created: ${offerEvents.length}`);
        console.log(`🛒 Transactions Created: ${transactionEvents.length}`);
        console.log(`✅ Transactions Verified: ${verifiedEvents.length}`);
        console.log(`🌲 Merkle Leaves Added: ${leafEvents.length}`);
        
        // Show latest activity
        if (allEvents.length > 0) {
            const latestEvent = allEvents[allEvents.length - 1];
            console.log(`\n🕐 Latest Activity:`);
            console.log(`- Event: ${latestEvent.eventName || 'Unknown'}`);
            console.log(`- Block: ${latestEvent.blockNumber}`);
            console.log(`- TX: ${latestEvent.transactionHash}`);
        }

        // Option to scan specific block range
        console.log("\n💡 To scan a specific block range:");
        console.log("   Modify fromBlock and toBlock variables in the script");
        console.log("\n💡 To scan from deployment:");
        console.log("   Set fromBlock = 0 (warning: may be slow)");

    } catch (error) {
        console.error("❌ Error reading events:", error.message);
        
        if (error.message.includes('invalid address')) {
            console.log("\n💡 Solution: Check the PRIVACY_POOL_ADDRESS");
        } else if (error.message.includes('network')) {
            console.log("\n💡 Solution: Make sure you're connected to the right network");
        } else if (error.message.includes('timeout')) {
            console.log("\n💡 Solution: Try reducing the block range");
        }
        
        process.exit(1);
    }
}

main()
    .then(() => {
        console.log("\n✅ Event reading completed successfully");
        process.exit(0);
    })
    .catch((error) => {
        console.error("\n❌ Script failed:", error);
        process.exit(1);
    });