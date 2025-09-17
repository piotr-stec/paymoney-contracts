const hre = require("hardhat");

// Helper function to convert byte array to hex string
function bytesToHex(bytes) {
  return "0x" + bytes.map(b => b.toString(16).padStart(2, '0')).join('');
}

// Alternative: Using Uint8Array directly
function createBytesFromArray(byteArray) {
  return new Uint8Array(byteArray);
}

async function main() {
  console.log("Testing verifyTransaction function...");

  // Get deployed contract address (you'll need to update this with actual deployed address)
  const PRIVACY_POOL_ADDRESS = "0x5A625f40B60a798055F44aBc26B8011807Af27dd" // Replace with actual deployed address
  
  // Library addresses from deployment on Sepolia
  const MERKLE_TREE_LIB_ADDRESS = "0xE08f869f3855A9617AfB82f61644Fb87AAe348cE"; // From deployment logs
  const POSEIDON_T3_ADDRESS = "0x43F59c9Fb08852da2e9C809d22466421D093426A"; // From deployment logs

  // Get contract instance with library linking
  const PrivacyPool = await hre.ethers.getContractFactory("PrivacyPool", {
    libraries: {
      "contracts/MerkleTreeLibrary.sol:MerkleTreeLib": MERKLE_TREE_LIB_ADDRESS,
      "lib/poseidon-solidity/contracts/PoseidonT3.sol:PoseidonT3": POSEIDON_T3_ADDRESS,
    },
  });
  const privacyPool = await PrivacyPool.attach(PRIVACY_POOL_ADDRESS);

  // Mock data for testing verifyTransaction
  const testData = {
    // Price proof data (can be empty for testing)
    proofPrice: "0x",
    publicInputsPrice: [],

    // Secret nullifier hash
    secretNullifierHash: "0x1234567890123456789012345678901234567890123456789012345678901234",

    // TLSN Signature data
    tlsnSignature: {
      key: bytesToHex([171, 23, 221, 91, 192, 195, 17, 100, 28, 95, 199, 229, 32, 144, 124, 177, 82, 106, 225, 70, 6, 80, 99, 217, 141, 164, 119, 17, 236, 111, 203, 156, 130, 18, 72, 32, 254, 85, 53, 240, 68, 83, 2, 57, 34, 127, 127, 192, 163, 158, 162, 128, 0, 215, 247, 105, 207, 115, 233, 75, 50, 113, 194, 24]), // 64 bytes
      message: bytesToHex([168, 195, 131, 157, 197, 144, 118, 43, 126, 101, 249, 131, 232, 72, 34, 229, 0, 0, 0, 0, 3, 32, 235, 248, 173, 168, 143, 218, 161, 179, 29, 24, 180, 245, 5, 107, 47, 101, 199, 209, 133, 84, 226, 194, 47, 16, 152, 219, 18, 25, 100, 79, 30, 126]), // 32 bytes 
      sig: bytesToHex([147, 17, 237, 174, 16, 137, 93, 141, 105, 165, 197, 61, 120, 170, 230, 40, 108, 197, 2, 237, 95, 88, 125, 27, 176, 132, 225, 226, 97, 215, 37, 205, 110, 95, 168, 109, 81, 166, 157, 52, 120, 159, 47, 35, 23, 160, 82, 84, 238, 233, 199, 230, 189, 181, 91, 32, 226, 118, 213, 108, 247, 101, 237, 232]) // 64 bytes
    },

    // TLSN Header data
    tlsnHeader: {
      header_root: bytesToHex([235, 248, 173, 168, 143, 218, 161, 179, 29, 24, 180, 245, 5, 107, 47, 101, 199, 209, 133, 84, 226, 194, 47, 16, 152, 219, 18, 25, 100, 79, 30, 126]), // Only 32 bytes
      body: {
        verifying_key_data: bytesToHex([1, 33, 2, 171, 23, 221, 91, 192, 195, 17, 100, 28, 95, 199, 229, 32, 144, 124, 177, 82, 106, 225, 70, 6, 80, 99, 217, 141, 164, 119, 17, 236, 111, 203, 156]),
        connection_info_data: bytesToHex([91, 15, 196, 104, 0, 0, 0, 0, 0, 186, 0, 0, 0, 156, 4, 0, 0]),
        server_ephemeral_key_data: bytesToHex([0, 65, 4, 39, 50, 213, 137, 164, 91, 174, 127, 62, 85, 208, 80, 159, 76, 95, 230, 124, 154, 202, 42, 251, 218, 126, 237, 185, 244, 40, 154, 229, 127, 52, 246, 165, 75, 52, 51, 51, 27, 136, 52, 179, 254, 36, 19, 151, 29, 56, 243, 48, 182, 116, 143, 178, 42, 29, 230, 66, 17, 154, 79, 90, 67, 8, 208]),
        cert_commitment_data: bytesToHex([3, 32, 226, 70, 97, 188, 219, 203, 4, 84, 150, 61, 16, 128, 46, 3, 193, 173, 197, 204, 72, 34, 21, 15, 198, 139, 28, 29, 46, 150, 68, 254, 235, 209]),
        transcript_commitments_data: bytesToHex([1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 156, 4, 0, 0, 0, 0, 0, 0, 1, 32, 91, 13, 59, 41, 80, 53, 87, 123, 93, 188, 4, 114, 39, 221, 157, 44, 234, 174, 61, 6, 3, 44, 130, 96, 220, 209, 161, 179, 238, 246, 154, 160]) // Must contain transcript commitment hash at position 21
      }
    },

    // TLSN Transcript data with actual bytes
    tlsnTranscript: {
      data: bytesToHex([72, 84, 84, 80, 47, 49, 46, 49, 32, 50, 48, 48, 32, 79, 75, 13, 10, 100, 97, 116, 101, 58, 32, 83, 97, 116, 44, 32, 50, 52, 32, 77, 97, 121, 32, 50, 48, 50, 53, 32, 49, 57, 58, 48, 53, 58, 50, 53, 32, 71, 77, 84, 13, 10, 99, 111, 110, 116, 101, 110, 116, 45, 116, 121, 112, 101, 58, 32, 97, 112, 112, 108, 105, 99, 97, 116, 105, 111, 110, 47, 106, 115, 111, 110, 59, 99, 104, 97, 114, 115, 101, 116, 61, 117, 116, 102, 45, 56, 13, 10, 99, 111, 110, 110, 101, 99, 116, 105, 111, 110, 58, 32, 99, 108, 111, 115, 101, 13, 10, 116, 114, 97, 110, 115, 102, 101, 114, 45, 101, 110, 99, 111, 100, 105, 110, 103, 58, 32, 99, 104, 117, 110, 107, 101, 100, 13, 10, 13, 10, 51, 70, 66, 13, 10, 91, 123, 34, 97, 99, 99, 111, 117, 110, 116, 34, 58, 123, 34, 105, 100, 34, 58, 34, 100, 55, 55, 102, 50, 53, 55, 102, 45, 100, 49, 97, 49, 45, 52, 48, 50, 99, 45, 97, 98, 97, 51, 45, 57, 52, 51, 51, 52, 102, 52, 49, 53, 100, 53, 97, 34, 44, 34, 116, 121, 112, 101, 34, 58, 34, 67, 85, 82, 82, 69, 78, 84, 34, 125, 44, 34, 97, 109, 111, 117, 110, 116, 34, 58, 45, 50, 44, 34, 97, 109, 111, 117, 110, 116, 87, 105, 116, 104, 67, 104, 97, 114, 103, 101, 115, 34, 58, 45, 50, 44, 34, 98, 97, 108, 97, 110, 99, 101, 34, 58, 53, 53, 50, 44, 34, 99, 97, 110, 99, 101, 108, 108, 97, 98, 108, 101, 34, 58, 102, 97, 108, 115, 101, 44, 34, 99, 97, 116, 101, 103, 111, 114, 121, 34, 58, 34, 116, 114, 97, 110, 115, 102, 101, 114, 115, 34, 44, 34, 99, 111, 109, 109, 101, 110, 116, 34, 58, 34, 52, 83, 81, 74, 68, 50, 102, 97, 105, 72, 89, 34, 44, 34, 99, 111, 109, 112, 108, 101, 116, 101, 100, 68, 97, 116, 101, 34, 58, 49, 55, 52, 54, 53, 53, 54, 52, 53, 55, 53, 49, 49, 44, 34, 99, 114, 101, 97, 116, 101, 100, 68, 97, 116, 101, 34, 58, 49, 55, 52, 54, 53, 53, 54, 52, 53, 55, 48, 49, 49, 44, 34, 99, 117, 114, 114, 101, 110, 99, 121, 34, 58, 34, 80, 76, 78, 34, 44, 34, 100, 101, 115, 99, 114, 105, 112, 116, 105, 111, 110, 34, 58, 34, 84, 111, 32, 80, 65, 87, 69, 76, 32, 68, 65, 82, 73, 85, 83, 90, 32, 78, 34, 44, 34, 102, 101, 101, 34, 58, 48, 44, 34, 103, 114, 111, 117, 112, 75, 101, 121, 34, 58, 34, 54, 56, 49, 97, 53, 54, 50, 57, 45, 100, 51, 51, 53, 45, 97, 52, 50, 50, 45, 57, 98, 102, 54, 45, 49, 52, 49, 55, 48, 50, 97, 51, 53, 102, 57, 49, 34, 44, 34, 105, 100, 34, 58, 34, 53, 34, 44, 34, 108, 101, 103, 73, 100, 34, 58, 34, 54, 56, 49, 97, 53, 54, 50, 57, 45, 100, 51, 51, 53, 45, 97, 52, 50, 50, 45, 48, 48, 48, 48, 45, 49, 52, 49, 55, 48, 50, 97, 51, 53, 102, 57, 49, 34, 44, 34, 108, 111, 99, 97, 108, 105, 115, 101, 100, 68, 101, 115, 99, 114, 105, 112, 116, 105, 111, 110, 34, 58, 123, 34, 107, 101, 121, 34, 58, 34, 116, 114, 97, 110, 115, 97, 99, 116, 105, 111, 110, 46, 100, 101, 115, 99, 114, 105, 112, 116, 105, 111, 110, 46, 103, 101, 110, 101, 114, 105, 99, 46, 110, 97, 109, 101, 34, 44, 34, 112, 97, 114, 97, 109, 115, 34, 58, 91, 123, 34, 107, 101, 121, 34, 58, 34, 110, 97, 109, 101, 34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 34, 80, 65, 87, 69, 76, 32, 68, 65, 82, 73, 85, 83, 90, 32, 78, 34, 125, 93, 125, 44, 34, 114, 97, 116, 101, 34, 58, 49, 44, 34, 114, 101, 99, 97, 108, 108, 97, 98, 108, 101, 34, 58, 102, 97, 108, 115, 101, 44, 34, 114, 101, 99, 105, 112, 105, 101, 110, 116, 34, 58, 123, 34, 97, 99, 99, 111, 117, 110, 116, 34, 58, 123, 34, 105, 100, 34, 58, 34, 97, 102, 56, 98, 49, 98, 55, 56, 45, 56, 98, 50, 98, 45, 52, 99, 101, 56, 45, 97, 49, 53, 55, 45, 48, 99, 55, 102, 102, 100, 49, 102, 97, 101, 102, 52, 34, 44, 34, 116, 121, 112, 101, 34, 58, 34, 67, 85, 82, 82, 69, 78, 84, 34, 125, 44, 34, 99, 111, 100, 101, 34, 58, 34, 112, 97, 119, 101, 117, 115, 101, 104, 116, 34, 44, 34, 99, 111, 117, 110, 116, 114, 121, 34, 58, 34, 80, 76, 34, 44, 34, 102, 105, 114, 115, 116, 78, 97, 109, 101, 34, 58, 34, 80, 65, 87, 69, 76, 32, 68, 65, 82, 73, 85, 83, 90, 34, 44, 34, 105, 100, 34, 58, 34, 56, 53, 100, 98, 100, 53, 52, 54, 45, 50, 53, 52, 98, 45, 52, 49, 49, 51, 45, 97, 55, 56, 53, 45, 53, 99, 54, 56, 98, 48, 54, 97, 53, 49, 100, 102, 34, 44, 34, 108, 97, 115, 116, 78, 97, 109, 101, 34, 58, 34, 78, 79, 87, 65, 75, 34, 44, 34, 116, 121, 112, 101, 34, 58, 34, 73, 78, 68, 73, 86, 73, 68, 85, 65, 76, 34, 44, 34, 117, 115, 101, 114, 110, 97, 109, 101, 34, 58, 34, 110, 101, 111, 116, 104, 101, 112, 114, 111, 103, 114, 97, 109, 105, 115, 116, 34, 125, 44, 34, 114, 101, 103, 105, 115, 116, 101, 114, 101, 100, 73, 100, 101, 110, 116, 105, 116, 121, 73, 100, 34, 58, 34, 100, 53, 49, 97, 100, 55, 102, 54, 45, 98, 98, 102, 48, 45, 52, 97, 54, 53, 45, 97, 50, 101, 48, 45, 101, 56, 97, 99, 56, 48, 98, 53, 48, 48, 48, 55, 34, 44, 34, 115, 116, 97, 114, 116, 101, 100, 68, 97, 116, 101, 34, 58, 49, 55, 52, 54, 53, 53, 54, 52, 53, 55, 48, 49, 49, 44, 34, 115, 116, 97, 116, 101, 34, 58, 34, 67, 79, 77, 80, 76, 69, 84, 69, 68, 34, 44, 34, 115, 117, 103, 103, 101, 115, 116, 105, 111, 110, 115, 34, 58, 91, 93, 44, 34, 116, 97, 103, 34, 58, 34, 116, 114, 97, 110, 115, 102, 101, 114, 115, 34, 44, 34, 116, 121, 112, 101, 34, 58, 34, 84, 82, 65, 78, 83, 70, 69, 82, 34, 44, 34, 117, 112, 100, 97, 116, 101, 100, 68, 97, 116, 101, 34, 58, 49, 55, 52, 54, 53, 53, 54, 52, 53, 55, 53, 49, 50, 125, 93, 13, 10, 48, 13, 10, 13, 10]),
      blinder: bytesToHex([241, 55, 162, 2, 59, 227, 35, 39, 244, 52, 40, 132, 163, 47, 129, 93])
    }
  };

  try {
    console.log("Calling verifyTransaction with test data...");

    const tx = await privacyPool.verifyTransaction(
      testData.proofPrice,
      testData.publicInputsPrice,
      testData.secretNullifierHash,
      testData.tlsnSignature,
      testData.tlsnHeader,
      testData.tlsnTranscript
    );

    console.log("Transaction sent:", tx.hash);

    // Wait for transaction to be mined
    const receipt = await tx.wait();
    console.log("Transaction mined in block:", receipt.blockNumber);
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("Transaction status:", receipt.status === 1 ? "SUCCESS" : "FAILED");

    // Check for events
    if (receipt.events && receipt.events.length > 0) {
      console.log("Events emitted:");
      receipt.events.forEach((event, index) => {
        console.log(`  Event ${index}:`, event.event, event.args);
      });
    } else {
      console.log("No events emitted");
    }

    if (receipt.status === 1) {
      console.log("✅ verifyTransaction completed successfully!");
    } else {
      console.log("❌ Transaction failed during execution");
    }

  } catch (error) {
    console.error("❌ verifyTransaction failed:");
    console.error("Error message:", error.message);

    if (error.reason) {
      console.error("Revert reason:", error.reason);
    }

    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

// Helper function to create mock TLSN data with proper structure
function createMockTlsnData(jsonData) {
  const jsonString = JSON.stringify(jsonData);
  const jsonBytes = hre.ethers.utils.toUtf8Bytes(jsonString);

  return {
    data: jsonBytes,
    blinder: hre.ethers.utils.randomBytes(32)
  };
}

// Allow script to be called from other scripts
if (require.main === module) {
  main()
    .then(() => {
      console.log("\n=== Test completed ===");
      process.exit(0);
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}

module.exports = { main, createMockTlsnData };