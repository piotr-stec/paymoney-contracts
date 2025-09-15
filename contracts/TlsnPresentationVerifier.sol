// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract TlsnPresentationVerifier {
    error InvalidSignatureLength();
    error InvalidKeyLength();
    error InvalidSignature();
    error InvalidSigner();
    error InvalidHeaderRoot();
    error InvalidTranscriptCommitment();

    event DebugHash(string label, bytes32 hash);
    event DebugDomain(string domain, bytes16 domainHash);

    event DebugStep(string step);

    struct SignatureData {
        bytes key;
        bytes message;
        bytes sig;
    }

    struct BodyVerification {
        bytes verifying_key_data;
        bytes connection_info_data;
        bytes server_ephemeral_key_data;
        bytes cert_commitment_data;
        bytes transcript_commitments_data;
    }

    struct HeaderVerification {
        bytes32 header_root;
        BodyVerification body;
    }

    struct TranscriptCommitment {
        bytes data;
        bytes blinder;
    }

    function verify(
        SignatureData memory signatureData,
        HeaderVerification memory headerVerification,
        TranscriptCommitment memory transcript
    ) public returns (bool) {
        emit DebugStep("Starting verification");

        // Message Verification
        emit DebugStep("Starting signature verification");
        if (!_verifySignature(signatureData)) revert InvalidSignature();
        emit DebugStep("Signature verification passed");

        // Header Verification
        bytes32[5] memory bodyFieldHashes = _hash_body_fields(
            headerVerification.body
        );
        bytes32 computedHeaderRoot = _compute_header_root(bodyFieldHashes);

        emit DebugHash("Expected header root", headerVerification.header_root);
        emit DebugHash("Computed header root", computedHeaderRoot);

        if (computedHeaderRoot != headerVerification.header_root)
            revert InvalidHeaderRoot();

        // Transcript Commitment Verification
        bytes32 hash = sha256(
            abi.encodePacked(transcript.data, transcript.blinder)
        );

        bytes32 transcriptCommitmentHash;
        bytes memory transcriptCommitments = headerVerification
            .body
            .transcript_commitments_data;
        assembly {
            transcriptCommitmentHash := mload(
                add(add(transcriptCommitments, 0x20), 21)
            )
        }
        emit DebugHash("hash", hash);
        emit DebugHash("transcriptCommitmentHash", transcriptCommitmentHash);

        if (hash != transcriptCommitmentHash)
            revert InvalidTranscriptCommitment();

        return true;
    }

    function _verifySignature(
        SignatureData memory signatureData
    ) internal returns (bool) {
        emit DebugStep("Checking key length");
        if (signatureData.key.length != 64) revert InvalidKeyLength();
        emit DebugStep("Checking sig length");
        if (signatureData.sig.length != 64) revert InvalidSignatureLength();
        emit DebugStep("Length checks passed");

        bytes32 messageHash = sha256(signatureData.message);

        bytes32 r;
        bytes32 s;

        bytes memory signature = signatureData.sig;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
        }

        address derivedAddress = address(
            uint160(uint256(keccak256(signatureData.key)))
        );
        address recoveredAddress = ecrecover(messageHash, 28, r, s);

        if (recoveredAddress != derivedAddress) {
            recoveredAddress = ecrecover(messageHash, 27, r, s);
        }

        if (recoveredAddress != derivedAddress) revert InvalidSigner();

        return true;
    }

    function _hash_body_fields(
        BodyVerification memory body
    ) internal returns (bytes32[5] memory) {
        bytes32[5] memory bodyFieldHashes;

        bytes16 domain0 = 0xaec37d45b99c4e4b637706b1e978a3eb;
        emit DebugDomain("VerifyingKey", domain0);
        bodyFieldHashes[0] = _hash_field(domain0, body.verifying_key_data);
        emit DebugHash("VerifyingKey hash", bodyFieldHashes[0]);

        bytes16 domain1 = 0x9d607992377bd411b39e6f8077397302;
        emit DebugDomain("ConnectionInfo", domain1);
        bodyFieldHashes[1] = _hash_field(domain1, body.connection_info_data);
        emit DebugHash("ConnectionInfo hash", bodyFieldHashes[1]);

        bytes16 domain2 = 0x6ed20378bc30d1ee44a4185787ada2e5;
        emit DebugDomain("ServerEphemKey", domain2);
        bodyFieldHashes[2] = _hash_field(
            domain2,
            body.server_ephemeral_key_data
        );
        emit DebugHash("ServerEphemKey hash", bodyFieldHashes[2]);

        bytes16 domain3 = 0xd0f7107feb7eec1e5793d2e8a2b696f0;
        emit DebugDomain("ServerCertCommitment", domain3);
        bodyFieldHashes[3] = _hash_field(domain3, body.cert_commitment_data);
        emit DebugHash("ServerCertCommitment hash", bodyFieldHashes[3]);

        bytes16 domain4 = 0x161bd651a50cb5fe173f69f255aebe9c;
        emit DebugDomain("TranscriptCommitment", domain4);
        bodyFieldHashes[4] = _hash_field(
            domain4,
            body.transcript_commitments_data
        );
        emit DebugHash("TranscriptCommitment hash", bodyFieldHashes[4]);

        return bodyFieldHashes;
    }

    function _hash_domain(
        string memory domain
    ) internal pure returns (bytes16) {
        bytes32 domainHash = keccak256(bytes(domain));
        bytes16 result;

        assembly {
            result := domainHash
        }

        return result;
    }

    function _hash_field(
        bytes16 domain,
        bytes memory data
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(domain, data));
    }

    function _compute_header_root(
        bytes32[5] memory bodyFieldHashes
    ) internal pure returns (bytes32) {
        // Level 1
        bytes32 h0 = _hash_pair(bodyFieldHashes[0], bodyFieldHashes[1]);
        bytes32 h1 = _hash_pair(bodyFieldHashes[2], bodyFieldHashes[3]);
        bytes32 h2 = bodyFieldHashes[4];

        // Level 2
        bytes32 h3 = _hash_pair(h0, h1);

        // Root
        bytes32 root = _hash_pair(h3, h2);

        return root;
    }

    function _hash_pair(
        bytes32 left,
        bytes32 right
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }
}
