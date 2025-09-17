// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./MerkleTreeLibrary.sol";
import "./TlsnVerificationLib.sol";
import "lib/poseidon-solidity/contracts/PoseidonT3.sol";

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

struct OfferParams {
    string currency;
    uint256 cryptoAmount;
    uint256 fiatAmount; // 0 for dynamic offers
    address tokenAddress;
    uint256 fee;
    string revTag;
}

enum TransactionStatus {
    PENDING,
    SUCCESS,
    REJECTED
}

struct Transaction {
    uint256 cryptoAmount;
    uint256 fiatAmount; // 0 for dynamic transactions
    string offerType;
    string currency;
    uint256 expiresAt;
    TransactionStatus status;
    string randomTitle;
    address tokenAddress;
    string revTag;
    uint256 timestamp;
    uint256 offerSecretHash; // Reference to original offer
}

enum OfferStatus {
    CREATED,
    CANCELLED
}

struct Offer {
    uint256 secretHash;
    string offerType;
    string currency;
    uint256 cryptoAmount;
    uint256 fiatAmount; // 0 for dynamic offers
    address tokenAddress;
    uint256 fee;
    OfferStatus status;
    string revTag;
    uint256 timestamp;
    uint256 cancelHash;
}

interface IVerifier {
    function verify(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external view returns (bool);
}

contract PrivacyPool {
    using MerkleTreeLib for MerkleTreeLib.Tree;
    using TlsnVerificationLib for *;

    // Storage
    MerkleTreeLib.Tree private tree;
    mapping(uint256 => bool) public nullifierHashes;

    address public owner;

    // Verifiers
    address public verifier;
    address public tlsnBinanceVerifier;

    // Offer state
    mapping(uint256 => Offer) public offers; // secretHash => Offer
    mapping(bytes32 => Transaction) public transactions; // transactionId => Transaction
    mapping(string => bytes32) public titleToTransactionId; // randomTitle => transactionId
    mapping(uint256 => bytes32[]) public offerTransactions; // offerSecretHash => transactionIds[]
    uint256[] public activeOffers; // Array of active offer secretHashes for enumeration

    // Events
    event Deposit(
        uint256 indexed secretNullifierHash,
        uint256 amount,
        address indexed token
    );

    event LeafAdded(
        address indexed caller,
        uint256 indexed commitment,
        uint256 newRoot
    );

    event OfferCreated(
        uint256 indexed secretHash,
        string indexed offerType,
        uint256 cryptoAmount,
        uint256 fiatAmount,
        string currency,
        address tokenAddress,
        string revTag
    );

    event TransactionCreated(
        bytes32 indexed transactionId,
        uint256 indexed offerSecretHash,
        string offerType,
        uint256 cryptoAmount,
        uint256 fiatAmount,
        string title
    );

    event TransactionVerified(
        bytes32 indexed transactionId,
        string comment,
        uint256 finalFiatAmount,
        uint256 cryptoToSend
    );

    event OfferCancelIntent(uint256 indexed offerSecretHash);
    event OfferCancelClaim(uint256 indexed offerSecretHash);

    // Errors
    error TransferFailed();
    error NullifierAlreadyUsed();
    error InvalidRoot();
    error OfferNotFound();
    error OfferAlreadyExists();
    error OfferNotActive();
    error UnauthorizedAccess();
    error TransferAlreadyExists();
    error TransferNotFound();
    error TransferExpired();
    error InvalidSecret();

    constructor(
        address _owner,
        address _verifier,
        address _tlsnBinanceVerifier
    ) {
        owner = _owner;
        verifier = _verifier;
        tlsnBinanceVerifier = _tlsnBinanceVerifier;
        tree.initialize();
    }

    // Privacy Pool external Functions
    function deposit(
        uint256 secretNullifierHash,
        uint256 amount,
        address token
    ) external {
        uint256 secretNullifierAmountHash = _poseidonHash(
            secretNullifierHash,
            amount
        );
        uint256 commitment = _poseidonHash(
            secretNullifierAmountHash,
            uint256(uint160(token))
        );

        IERC20 erc20 = IERC20(token);
        bool success = erc20.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Add to merkle tree
        tree.addLeaf(commitment);
        emit Deposit(secretNullifierHash, amount, token);
    }

    function withdraw(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external {
        IVerifier honkVerifier = IVerifier(verifier);
        if (!honkVerifier.verify(proof, publicInputs)) {
            revert("Invalid proof");
        }
        uint256 root_1 = uint256(publicInputs[0]);
        uint256 nullifier_1 = uint256(publicInputs[1]);
        address token_address_1 = address(uint160(uint256(publicInputs[2])));
        uint256 amount = uint256(publicInputs[3]);
        uint256 refund_commitment_hash = uint256(publicInputs[4]);
        address recipient = address(uint160(uint256(publicInputs[5])));

        // Check if nullifiers already used
        if (nullifierHashes[nullifier_1]) {
            revert NullifierAlreadyUsed();
        }

        // Check if merkle roots are valid
        if (!tree.isValidRoot(root_1)) {
            revert InvalidRoot();
        }

        // Mark nullifiers as used
        nullifierHashes[nullifier_1] = true;

        // Add refund commitments to tree
        tree.addLeaf(refund_commitment_hash);

        // Transfer tokens to recipient
        IERC20 erc20_1 = IERC20(token_address_1);
        bool success = erc20_1.transfer(recipient, amount);
        if (!success) revert TransferFailed();
    }

    // Paymoney offer Functions
    function createOffer(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        uint256 secretHash,
        OfferParams calldata params
    ) external {
        // Validate proof
        IVerifier honkVerifier = IVerifier(verifier);
        if (!honkVerifier.verify(proof, publicInputs)) {
            revert("Invalid proof");
        }

        // Validate nullifiers and roots
        _validateNullifiersAndRoots(publicInputs);

        // Validate offer parameters
        _validateOfferParameters(
            publicInputs,
            params.tokenAddress,
            params.cryptoAmount,
            params.fee,
            secretHash
        );

        // Determine offer type based on fiatAmount - fiat amount == 0 -> dynamic else static
        string memory offerType = params.fiatAmount > 0 ? "static" : "dynamic";

        // Process offer creation
        _processOfferCreation(
            publicInputs,
            secretHash,
            offerType,
            params.currency,
            params.cryptoAmount,
            params.fiatAmount,
            params.tokenAddress,
            params.fee,
            params.revTag
        );
    }

    function cancelIntent(uint256 offerSecret, uint256 cancelHash) external {
        uint256 offerSecretHash = _poseidonHash(offerSecret, offerSecret);
        Offer storage offer = offers[offerSecretHash];
        require(offer.status == OfferStatus.CREATED, "Offer not active");
        offer.status = OfferStatus.CANCELLED;
        offer.cancelHash = cancelHash;

        // Remove from active offers array
        _removeFromActiveOffers(offerSecretHash);

        emit OfferCancelIntent(offerSecretHash);
    }

    function cancelClaim(
        uint256 offerHash,
        uint256 cancelSecret,
        uint256 secretNullifierHash
    ) external {
        uint256 offerCancelHash = _poseidonHash(cancelSecret, cancelSecret);
        Offer memory offer = offers[offerHash];

        require(offer.status == OfferStatus.CANCELLED, "Offer not cancelled");

        require(offer.cancelHash == offerCancelHash, "Invalid cancel hash");

        emit OfferCancelClaim(offerCancelHash);

        uint256 cryptoAmountToRefund = _getAvailableOfferAmount(offerHash);

        uint256 secretNullifierAmountHash = _poseidonHash(
            secretNullifierHash,
            cryptoAmountToRefund
        );
        uint256 commitment = _poseidonHash(
            secretNullifierAmountHash,
            uint256(uint160(offer.tokenAddress))
        );

        // Add to merkle tree
        tree.addLeaf(commitment);
        emit Deposit(
            secretNullifierHash,
            cryptoAmountToRefund,
            offer.tokenAddress
        );
    }

    function timeOutPendingTransactions(uint256 offerHash) external {
        bytes32[] storage txnIds = offerTransactions[offerHash];

        for (uint256 i = 0; i < txnIds.length; i++) {
            Transaction storage txn = transactions[txnIds[i]];

            if (
                txn.status == TransactionStatus.PENDING &&
                txn.expiresAt < block.timestamp
            ) {
                txn.status = TransactionStatus.REJECTED;
            }
        }
    }

    // Paymoney transaction Functions
    function createTransaction(
        uint256 offerSecretHash,
        uint256 cryptoAmount,
        string calldata title
    ) external returns (bytes32) {
        require(offers[offerSecretHash].timestamp != 0, "Offer not found");

        // Get offer data
        Offer memory offer = offers[offerSecretHash];
        require(offer.status == OfferStatus.CREATED, "Offer not active");
        require(cryptoAmount <= offer.cryptoAmount, "Amount exceeds offer");

        // Check if enough crypto is available (not locked in pending/completed transactions)
        uint256 availableAmount = _getAvailableOfferAmount(offerSecretHash);
        require(
            cryptoAmount <= availableAmount,
            "Insufficient available crypto in offer"
        );

        // Generate transaction ID
        bytes32 transactionId = keccak256(
            abi.encodePacked(
                offerSecretHash,
                cryptoAmount,
                title,
                block.timestamp,
                msg.sender
            )
        );

        require(
            transactions[transactionId].timestamp == 0,
            "Transaction already exists"
        );

        // Calculate fiat amount based on offer type
        uint256 fiatAmount;
        bool isStaticOffer = keccak256(bytes(offer.offerType)) ==
            keccak256(bytes("static"));

        if (isStaticOffer) {
            require(offer.fiatAmount > 0, "Invalid static offer");
            // Static offer: calculate proportional fiat amount
            fiatAmount = (offer.fiatAmount * cryptoAmount) / offer.cryptoAmount;
        } else {
            require(
                keccak256(bytes(offer.offerType)) ==
                    keccak256(bytes("dynamic")),
                "Invalid offer type"
            );
            fiatAmount = 0;
        }

        // Create transaction
        transactions[transactionId] = Transaction({
            cryptoAmount: cryptoAmount,
            fiatAmount: fiatAmount,
            offerType: offer.offerType,
            currency: offer.currency,
            expiresAt: block.timestamp + 60 minutes,
            status: TransactionStatus.PENDING,
            randomTitle: title,
            tokenAddress: offer.tokenAddress,
            revTag: offer.revTag,
            timestamp: block.timestamp,
            offerSecretHash: offerSecretHash
        });

        // Map title to transaction ID for lookup
        titleToTransactionId[title] = transactionId;

        // Track this transaction for the offer
        offerTransactions[offerSecretHash].push(transactionId);

        emit TransactionCreated(
            transactionId,
            offerSecretHash,
            offer.offerType,
            cryptoAmount,
            fiatAmount,
            title
        );

        return transactionId;
    }

    function verifyTransaction(
        bytes calldata proofPrice,
        bytes32[] calldata publicInputsPrice,
        uint256 secretNullifierHash,
        TlsnVerificationLib.SignatureData calldata tlsnSignature,
        TlsnVerificationLib.HeaderVerification calldata tlsnHeader,
        TlsnVerificationLib.TranscriptCommitment calldata tlsnTranscript
    ) external {
        // Step 1: Verify TLSN proof using TlsnVerificationLib
        bool verifiedTlsn = TlsnVerificationLib.verify(tlsnSignature, tlsnHeader, tlsnTranscript);
        require(verifiedTlsn, "TLSN verification failed");

        // Step 2: Verify standard proof and find transaction ID
        bytes32 transactionId = _findTransaction(tlsnTranscript);

        // // Step 2: Validate transaction and extract data
        _validateTransactionAndExtractData(transactionId, tlsnTranscript);

        // Step 3: Handle offer type specific processing
        Transaction storage txn = transactions[transactionId];

        uint256 cryptoAmountToSend;

        if (keccak256(bytes(txn.offerType)) == keccak256(bytes("dynamic"))) {
            cryptoAmountToSend = _processDynamicOffer(
                proofPrice,
                publicInputsPrice,
                transactionId
            );
        } else {
            cryptoAmountToSend = _processStaticOffer(transactionId);
        }

        // Mark transaction as successful
        txn.status = TransactionStatus.SUCCESS;
        emit TransactionVerified(
            transactionId,
            "",
            txn.fiatAmount,
            cryptoAmountToSend
        );

        uint256 secretNullifierAmountHash = _poseidonHash(
            secretNullifierHash,
            cryptoAmountToSend
        );
        uint256 commitment = _poseidonHash(
            secretNullifierAmountHash,
            uint256(uint160(txn.tokenAddress))
        );

        // Add to merkle tree
        tree.addLeaf(commitment);
        emit Deposit(secretNullifierHash, cryptoAmountToSend, txn.tokenAddress);

        if (_getAvailableOfferAmount(txn.offerSecretHash) <= 0) {
            _removeFromActiveOffers(txn.offerSecretHash);
        }
    }

    function _findTransaction(
        TlsnVerificationLib.TranscriptCommitment memory tlsnTranscript
    ) internal view returns (bytes32) {
        // Extract comment and find transaction
        string memory commentData = _extractCommentFromTranscript(
            tlsnTranscript
        );
        bytes32 transactionId = titleToTransactionId[commentData];
        require(
            transactionId != bytes32(0),
            "Transaction not found for comment"
        );

        return transactionId;
    }

    function _validateTransactionAndExtractData(
        bytes32 transactionId,
        TlsnVerificationLib.TranscriptCommitment memory tlsnTranscript
    ) internal {
        Transaction storage txn = transactions[transactionId];
        require(txn.timestamp != 0, "Transaction not found");
        require(
            txn.status == TransactionStatus.PENDING,
            "Transaction not pending"
        );
        require(block.timestamp <= txn.expiresAt, "Transaction expired");

        // Extract and validate data
        uint256 fiatAmountTransferred = _extractAmountFromTranscript(
            tlsnTranscript
        );
        string memory extractedRevTag = _extractUsernameFromTranscript(
            tlsnTranscript
        );

        require(
            keccak256(bytes(extractedRevTag)) == keccak256(bytes(txn.revTag)),
            "RevTag mismatch"
        );

        // Update transaction with actual transferred amount
        txn.fiatAmount = fiatAmountTransferred;
    }

    function _processDynamicOffer(
        bytes calldata proofPrice,
        bytes32[] calldata publicInputsPrice,
        bytes32 transactionId
    ) internal view returns (uint256) {
        require(
            proofPrice.length > 0,
            "Price proof required for dynamic offers"
        );

        if (
            !IVerifier(tlsnBinanceVerifier).verify(
                proofPrice,
                publicInputsPrice
            )
        ) {
            revert("Invalid price proof");
        }

        // Extract exchange rate from price proof
        uint256 exchangeRate = extractCleanPrice(publicInputsPrice);

        // For dynamic offers, the fiat amount was already set from extracted transaction data
        // We validate that the price proof is legitimate
        require(exchangeRate > 0, "Invalid exchange rate");

        Transaction storage txn = transactions[transactionId];

        // Calculate how much crypto to send based on fiat amount transferred and exchange rate
        // Formula: cryptoAmount = fiatAmount / exchangeRate
        // Example: 2 PLN (cents) / 362596667 (rate with 8 decimals) = crypto amount

        uint256 cryptoAmountToSend = calculateCryptoForDeposit(
            txn.fiatAmount, // Fiat amount transferred (e.g., 2 for 0.02 PLN)
            2, // Fiat decimals (PLN cents = 2 decimals)
            exchangeRate, // Exchange rate from Binance (8 decimals)
            6 // Crypto decimals
        );

        return cryptoAmountToSend;
    }

    function _processStaticOffer(
        bytes32 transactionId
    ) internal view returns (uint256) {
        Transaction storage txn = transactions[transactionId];

        require(txn.fiatAmount > 0, "Invalid fiat amount for static offer");

        // Get the original offer using stored reference
        Offer storage offer = offers[txn.offerSecretHash];
        require(offer.fiatAmount > 0, "Invalid offer fiat amount");
        require(offer.cryptoAmount > 0, "Invalid offer crypto amount");

        // Calculate proportional crypto amount for static offers
        // Formula: cryptoToSend = (fiatTransferred / totalFiatPrice) * totalCryptoAmount
        // Example: If offer is 100 crypto for 1000 fiat, and user sent 500 fiat
        // Then: cryptoToSend = (500 / 1000) * 100 = 50 crypto
        uint256 cryptoAmountToSend = (txn.fiatAmount * offer.cryptoAmount) /
            offer.fiatAmount;

        // Ensure we don't send more crypto than available in the offer
        require(
            cryptoAmountToSend <= offer.cryptoAmount,
            "Exceeds available crypto in offer"
        );

        return cryptoAmountToSend;
    }

    // Internal Functions
    function _poseidonHash(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        uint256[2] memory inputs = [a, b];
        return PoseidonT3.hash(inputs);
    }

    function _extractCommentFromTranscript(
        TlsnVerificationLib.TranscriptCommitment memory transcript
    ) internal pure returns (string memory) {
        return _extractJsonField(transcript.data, "comment");
    }

    function _extractAmountFromTranscript(
        TlsnVerificationLib.TranscriptCommitment memory transcript
    ) internal pure returns (uint256) {
        string memory amountStr = _extractJsonField(transcript.data, "amount");
        return _parseUnsignedInt(amountStr);
    }

    function _extractCurrencyFromTranscript(
        TlsnVerificationLib.TranscriptCommitment memory transcript
    ) internal pure returns (string memory) {
        return _extractJsonField(transcript.data, "currency");
    }

    function _extractUsernameFromTranscript(
        TlsnVerificationLib.TranscriptCommitment memory transcript
    ) internal pure returns (string memory) {
        // Username is in nested structure: "recipient":{"username":"value"}
        return
            _extractNestedJsonField(transcript.data, "recipient", "username");
    }

    function _extractJsonField(
        bytes memory data,
        string memory fieldName
    ) internal pure returns (string memory) {
        bytes memory fieldPattern = abi.encodePacked('"', fieldName, '":"');

        for (uint256 i = 0; i < data.length - fieldPattern.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < fieldPattern.length; j++) {
                if (data[i + j] != fieldPattern[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                uint256 startPos = i + fieldPattern.length;
                uint256 endPos = startPos;

                // Find closing quote
                for (uint256 k = startPos; k < data.length; k++) {
                    if (data[k] == '"') {
                        endPos = k;
                        break;
                    }
                }

                if (endPos > startPos) {
                    bytes memory result = new bytes(endPos - startPos);
                    for (uint256 k = 0; k < endPos - startPos; k++) {
                        result[k] = data[startPos + k];
                    }
                    return string(result);
                }
            }
        }

        return "";
    }

    function _extractNestedJsonField(
        bytes memory data,
        string memory parentField,
        string memory childField
    ) internal pure returns (string memory) {
        bytes memory parentPattern = abi.encodePacked('"', parentField, '":{');

        for (uint256 i = 0; i < data.length - parentPattern.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < parentPattern.length; j++) {
                if (data[i + j] != parentPattern[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                // Found parent object, now search for child field within it
                uint256 startSearch = i + parentPattern.length;
                uint256 objectEnd = startSearch;
                uint256 braceCount = 1;

                // Find the end of the parent object
                for (
                    uint256 k = startSearch;
                    k < data.length && braceCount > 0;
                    k++
                ) {
                    if (data[k] == "{") braceCount++;
                    else if (data[k] == "}") braceCount--;
                    objectEnd = k;
                }

                // Extract the parent object data
                bytes memory objectData = new bytes(objectEnd - startSearch);
                for (uint256 k = 0; k < objectEnd - startSearch; k++) {
                    objectData[k] = data[startSearch + k];
                }

                // Now extract the child field from this object
                return _extractJsonField(objectData, childField);
            }
        }

        return "";
    }

    function _parseSignedInt(string memory str) internal pure returns (int256) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) return 0;

        bool negative = false;
        uint256 startIndex = 0;

        if (strBytes[0] == "-") {
            negative = true;
            startIndex = 1;
        }

        uint256 result = 0;
        for (uint256 i = startIndex; i < strBytes.length; i++) {
            uint8 digit = uint8(strBytes[i]);
            if (digit >= 0x30 && digit <= 0x39) {
                result = result * 10 + (digit - 0x30);
            }
        }

        return negative ? -int256(result) : int256(result);
    }

    function _parseUnsignedInt(
        string memory str
    ) internal pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length == 0) return 0;

        uint256 startIndex = 0;

        // Skip minus sign if present (convert -2 to 2)
        if (strBytes[0] == "-") {
            startIndex = 1;
        }

        uint256 result = 0;
        for (uint256 i = startIndex; i < strBytes.length; i++) {
            uint8 digit = uint8(strBytes[i]);
            if (digit >= 0x30 && digit <= 0x39) {
                result = result * 10 + (digit - 0x30);
            }
        }

        return result;
    }

    function _extractFiatAmount(
        bytes32[] calldata publicInputs,
        uint8 amountLength
    ) internal pure returns (uint256) {
        // Amount format: "amount":-2
        // Starts at index 76, extract the numeric value after the minus sign
        uint256 startIndex = 76 + 10; // "amount":- = 10 characters

        bytes memory amountBytes = new bytes(amountLength);
        for (uint256 i = 0; i < amountLength; i++) {
            amountBytes[i] = bytes1(
                uint8(uint256(publicInputs[startIndex + i]))
            );
        }

        // Convert bytes to number
        uint256 result = 0;
        for (uint256 i = 0; i < amountLength; i++) {
            uint8 digit = uint8(amountBytes[i]);
            if (digit >= 0x30 && digit <= 0x39) {
                // '0'-'9'
                result = result * 10 + (digit - 0x30);
            }
        }

        return result;
    }

    function _extractRevTag(
        bytes32[] calldata publicInputs,
        uint8 revTagLength
    ) internal pure returns (string memory) {
        // Username format: "username":"value"
        // Starts at index 105, extract the value between quotes
        uint256 startIndex = 105 + 12; // "username":" = 12 characters

        // Calculate actual value length (excluding quotes and JSON formatting)
        // revTagLength is total length (23), minus "username":"" (13 chars), minus closing quote (1 char) = 9 chars
        uint256 valueLength = revTagLength - 13; // Remove "username":" and closing "

        bytes memory revTagBytes = new bytes(valueLength);
        for (uint256 i = 0; i < valueLength; i++) {
            revTagBytes[i] = bytes1(
                uint8(uint256(publicInputs[startIndex + i]))
            );
        }

        return string(revTagBytes);
    }

    function _getAvailableOfferAmount(
        uint256 offerSecretHash
    ) internal view returns (uint256) {
        Offer storage offer = offers[offerSecretHash];
        uint256 totalUsed = 0;

        // Go through all transactions for this offer
        bytes32[] storage txnIds = offerTransactions[offerSecretHash];

        for (uint256 i = 0; i < txnIds.length; i++) {
            Transaction storage txn = transactions[txnIds[i]];

            // Count pending and completed transactions (not cancelled/expired)
            if (
                txn.status == TransactionStatus.PENDING ||
                txn.status == TransactionStatus.SUCCESS
            ) {
                totalUsed += txn.cryptoAmount;
            }
        }

        if (totalUsed >= offer.cryptoAmount) {
            return 0;
        }

        return offer.cryptoAmount - totalUsed;
    }

    function _checkPendingTransactions(
        uint256 offerSecretHash
    ) internal view returns (bool) {
        // Go through all transactions for this offer
        bytes32[] storage txnIds = offerTransactions[offerSecretHash];

        for (uint256 i = 0; i < txnIds.length; i++) {
            Transaction storage txn = transactions[txnIds[i]];

            if (txn.status == TransactionStatus.PENDING) {
                return true;
            }
        }

        return false;
    }

    function getAvailableOfferAmount(
        uint256 offerSecretHash
    ) external view returns (uint256) {
        return _getAvailableOfferAmount(offerSecretHash);
    }

    function getActiveOffersCount() external view returns (uint256) {
        return activeOffers.length;
    }

    function getActiveOffers(
        uint256 offset,
        uint256 limit
    ) external view returns (Offer[] memory) {
        uint256 totalOffers = activeOffers.length;

        if (offset >= totalOffers) {
            return new Offer[](0);
        }

        uint256 end = offset + limit;
        if (end > totalOffers) {
            end = totalOffers;
        }

        uint256 resultLength = end - offset;
        Offer[] memory result = new Offer[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            uint256 offerHash = activeOffers[offset + i];
            result[i] = offers[offerHash];
        }

        return result;
    }

    function getAllActiveOffers() external view returns (Offer[] memory) {
        Offer[] memory result = new Offer[](activeOffers.length);

        for (uint256 i = 0; i < activeOffers.length; i++) {
            uint256 offerHash = activeOffers[i];
            result[i] = offers[offerHash];
        }

        return result;
    }
    function _removeFromActiveOffers(uint256 offerSecretHash) internal {
        for (uint256 i = 0; i < activeOffers.length; i++) {
            if (activeOffers[i] == offerSecretHash) {
                // Move the last element to the current position and remove the last element
                activeOffers[i] = activeOffers[activeOffers.length - 1];
                activeOffers.pop();
                break;
            }
        }
    }

    // Extract clean price value from Binance API format: "price":"3.62596667"
    // Binance always returns exactly 8 decimal places
    function extractCleanPrice(
        bytes32[] calldata publicInputs
    ) internal pure returns (uint256) {
        // Extract raw price data
        bytes memory priceData = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            priceData[i] = bytes1(uint8(uint256(publicInputs[70 + i])));
        }

        // Find the numeric value between quotes after ":"
        // Format: "price":"3.62596667"
        uint256 start = 0;
        uint256 end = 0;
        bool foundColon = false;
        bool foundSecondQuote = false;

        for (uint256 i = 0; i < 20; i++) {
            if (priceData[i] == 0x3A) {
                // ':'
                foundColon = true;
            } else if (foundColon && priceData[i] == 0x22) {
                // '"' after colon
                if (!foundSecondQuote) {
                    start = i + 1; // Start after the quote
                    foundSecondQuote = true;
                } else {
                    end = i; // End at the closing quote
                    break;
                }
            }
        }

        // Parse decimal number - Binance always has exactly 8 decimal places
        uint256 result = 0;
        bool foundDot = false;

        for (uint256 i = start; i < end; i++) {
            uint8 char = uint8(priceData[i]);
            if (char == 0x2E) {
                // '.'
                foundDot = true;
            } else if (char >= 0x30 && char <= 0x39) {
                // '0'-'9'
                result = result * 10 + (char - 0x30);
            }
        }

        // Result is already in the correct format (8 decimal places)
        // Example: "3.62596667" -> 362596667
        return result;
    }

    function calculateCryptoForDeposit(
        uint256 fiatAmount, // Fiat amount deposited
        uint8 fiatDecimals, // Fiat token decimals (e.g., 2 for PLN cents)
        uint256 exchangeRate, // Exchange rate (crypto/fiat) with 8 decimals from Binance
        uint8 cryptoDecimals // Crypto token decimals (e.g., 6 for USDC, 18 for ETH)
    ) public pure returns (uint256) {
        // Formula: crypto_amount = fiat_amount / exchange_rate

        // Step 1: Normalize fiat amount to match rate precision (8 decimals)
        uint256 fiatWith8Decimals = fiatAmount * (10 ** (8 - fiatDecimals));

        // Step 2: Calculate crypto amount with 8 decimal precision
        uint256 cryptoWith8Decimals = (fiatWith8Decimals * 10 ** 8) /
            exchangeRate;

        // Step 3: Convert to target crypto token decimals
        if (cryptoDecimals >= 8) {
            // Scale up (e.g., for ETH with 18 decimals)
            return cryptoWith8Decimals * (10 ** (cryptoDecimals - 8));
        } else {
            // Scale down (e.g., for USDC with 6 decimals)
            return cryptoWith8Decimals / (10 ** (8 - cryptoDecimals));
        }
    }

    // Internal paymoney functions
    function _validateNullifiersAndRoots(
        bytes32[] calldata publicInputs
    ) internal view {
        uint256 nullifier_1 = uint256(publicInputs[1]);

        if (nullifierHashes[nullifier_1]) {
            revert NullifierAlreadyUsed();
        }

        if (!tree.isValidRoot(uint256(publicInputs[0]))) {
            revert InvalidRoot();
        }
    }

    function _validateOfferParameters(
        bytes32[] calldata publicInputs,
        address tokenAddress,
        uint256 cryptoAmount,
        uint256 fee,
        uint256 secretHash
    ) internal view {
        address token_address_1 = address(uint160(uint256(publicInputs[2])));
        uint256 amount = uint256(publicInputs[3]);

        require(token_address_1 == tokenAddress, "Token address mismatch");
        require(amount >= cryptoAmount + fee, "Insufficient deposit amount");

        if (offers[secretHash].timestamp != 0) {
            revert OfferAlreadyExists();
        }
    }

    function getCurrentRoot() external view returns (uint256) {
        return tree.currentRoot;
    }

    function _processOfferCreation(
        bytes32[] calldata publicInputs,
        uint256 secretHash,
        string memory offerType,
        string memory currency,
        uint256 cryptoAmount,
        uint256 fiatAmount,
        address tokenAddress,
        uint256 fee,
        string memory revTag
    ) internal {
        // Mark nullifiers as used
        nullifierHashes[uint256(publicInputs[1])] = true;

        // Add refund commitments to tree
        tree.addLeaf(uint256(publicInputs[4]));

        // Store offer
        offers[secretHash] = Offer({
            secretHash: secretHash,
            offerType: offerType,
            currency: currency,
            cryptoAmount: cryptoAmount,
            fiatAmount: fiatAmount,
            tokenAddress: tokenAddress,
            fee: fee,
            status: OfferStatus.CREATED,
            revTag: revTag,
            timestamp: block.timestamp,
            cancelHash: 0
        });

        // Add to active offers array
        activeOffers.push(secretHash);

        // Emit event
        emit OfferCreated(
            secretHash,
            offerType,
            cryptoAmount,
            fiatAmount,
            currency,
            tokenAddress,
            revTag
        );
    }
}
