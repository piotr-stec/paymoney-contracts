// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./MerkleTreeLibrary.sol";
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

struct Transaction {
    uint256 cryptoAmount;
    uint256 fiatAmount; // 0 for dynamic transactions
    string offerType;
    string currency;
    uint256 expiresAt;
    string status; // "pending", "success", "rejected"
    string randomTitle;
    address tokenAddress;
    string revTag;
    uint256 timestamp;
}

struct Offer {
    uint256 secretHash;
    string offerType;
    string currency;
    uint256 cryptoAmount;
    uint256 fiatAmount; // 0 for dynamic offers
    address tokenAddress;
    uint256 fee;
    string status;
    string revTag;
    uint256 timestamp;
}

interface IVerifier {
    function verify(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external view returns (bool);
}

contract PrivacyPool {
    using MerkleTreeLib for MerkleTreeLib.Tree;

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

    // Errors
    error TransferFailed();
    error NullifierAlreadyUsed();
    error InvalidRoot();
    error UnsupportedVerificationKey();
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
        uint256 root_2 = uint256(publicInputs[4]);
        uint256 nullifier_2 = uint256(publicInputs[5]);
        // unused for now
        address token_address_2 = address(uint160(uint256(publicInputs[6])));
        uint256 gas_fee = uint256(publicInputs[7]);
        uint256 refund_commitment_hash = uint256(publicInputs[8]);
        uint256 refund_commitment_hash_fee = uint256(publicInputs[9]);
        address recipient = address(uint160(uint256(publicInputs[10])));

        // Check if nullifiers already used
        if (nullifierHashes[nullifier_1]) {
            revert NullifierAlreadyUsed();
        }
        if (nullifierHashes[nullifier_2]) {
            revert NullifierAlreadyUsed();
        }

        // Check if merkle roots are valid
        if (!tree.isValidRoot(root_1)) {
            revert InvalidRoot();
        }
        if (!tree.isValidRoot(root_2)) {
            revert InvalidRoot();
        }

        // Mark nullifiers as used
        nullifierHashes[nullifier_1] = true;
        nullifierHashes[nullifier_2] = true;

        // Add refund commitments to tree
        tree.addLeaf(refund_commitment_hash);
        tree.addLeaf(refund_commitment_hash_fee);

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

    // Paymoney transaction Functions
    function createTransaction(
        uint256 offerSecretHash,
        uint256 cryptoAmount,
        string calldata title
    ) external returns (bytes32) {
        require(offers[offerSecretHash].timestamp != 0, "Offer not found");

        // Get offer data
        Offer memory offer = offers[offerSecretHash];
        require(
            keccak256(bytes(offer.status)) == keccak256(bytes("CREATED")),
            "Offer not active"
        );
        require(cryptoAmount <= offer.cryptoAmount, "Amount exceeds offer");

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
            status: "pending",
            randomTitle: title,
            tokenAddress: offer.tokenAddress,
            revTag: offer.revTag,
            timestamp: block.timestamp
        });

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
        bytes calldata proofTransaction,
        bytes32[] calldata publicInputsTransaction,
        bytes calldata proofPrice, // For static offers, proofPrice and publicInputsPrice can be empty
        bytes32[] calldata publicInputsPrice,
        address tlsnTransactionVerifier,
        uint256 secretNullifierHash
    ) external {
        // Verify proof
        IVerifier honkVerifier = IVerifier(tlsnTransactionVerifier);
        if (!honkVerifier.verify(proofTransaction, publicInputsTransaction)) {
            revert("Invalid proof");
        }

        // Verify proof
        IVerifier honkBinanceVerifier = IVerifier(tlsnBinanceVerifier);
        if (!honkBinanceVerifier.verify(proofPrice, publicInputsPrice)) {
            revert("Invalid proof");
        }
    }

    // Internal Functions
    function _poseidonHash(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        uint256[2] memory inputs = [a, b];
        return PoseidonT3.hash(inputs);
    }

    // Internal paymoney functions
    function _validateNullifiersAndRoots(
        bytes32[] calldata publicInputs
    ) internal view {
        uint256 nullifier_1 = uint256(publicInputs[1]);
        uint256 nullifier_2 = uint256(publicInputs[5]);

        if (nullifierHashes[nullifier_1] || nullifierHashes[nullifier_2]) {
            revert NullifierAlreadyUsed();
        }

        if (
            !tree.isValidRoot(uint256(publicInputs[0])) ||
            !tree.isValidRoot(uint256(publicInputs[4]))
        ) {
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
        nullifierHashes[uint256(publicInputs[5])] = true;

        // Add refund commitments to tree
        tree.addLeaf(uint256(publicInputs[8]));
        tree.addLeaf(uint256(publicInputs[9]));

        // Store offer
        offers[secretHash] = Offer({
            secretHash: secretHash,
            offerType: offerType,
            currency: currency,
            cryptoAmount: cryptoAmount,
            fiatAmount: fiatAmount,
            tokenAddress: tokenAddress,
            fee: fee,
            status: "CREATED",
            revTag: revTag,
            timestamp: block.timestamp
        });

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
