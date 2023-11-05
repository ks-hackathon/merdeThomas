// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import "./Verifier.sol";

contract AliceRingToken is ERC721, ERC721URIStorage, Ownable,FunctionsClient {
    uint256 private _nextTokenId;
     using FunctionsRequest for FunctionsRequest.Request;
    /*uint256 equalTrue=; 
    uint256 equalFalse=;*/
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    uint32 gaslimit = 50000;
    bytes32 donId =0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    mapping(bytes32 => address) private requestToSender;
    mapping (bytes32=>string) private requestToURI;

    event Response(bytes32 indexed requestId, bytes response, bytes err);

    enum Status {
        UNKNOWN, // the proof has not been verified on-chain, no proof has been minted
        MINTED // the proof has already been minted
    }

    
struct SignatureData {
    string message;
    uint256[] ring;
    uint256[] responses;
    uint256 c;
}

    error AlreadyMinted(string proofId);
    error InvalidSignature();
    error OnlyOwnerCanBurn(uint256 tokenId);
    error UnexpectedRequestID(bytes32 requestId);

    RingSigVerifier public verifier; // Instance of the ring signature verifier contract
    mapping(string => Status) public mintStatus; // signatureHash => Status (computed off-chain)

    constructor(
        address _verifier,
        address router 
    ) ERC721("AliceRingToken", "ART") Ownable(msg.sender) FunctionsClient(router)  {
        verifier = RingSigVerifier(_verifier);
    }

    // The following functions are overrides required by Solidity.
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice safeTransferFrom is disabled because the nft is a sbt
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public pure override(ERC721, IERC721) {
        revert("SBT: SafeTransfer not allowed");
    }

    /**
     * @notice transferFrom is disabled because the nft is a sbt
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public pure override(ERC721, IERC721) {
        revert("SBT: Transfer not allowed");
    }

    /**
     * @notice approve is disabled because the nft is a sbt and cannot be transferred
     */
    function approve(
        address to,
        uint256 tokenId
    ) public pure override(ERC721, IERC721) {
        revert("SBT: Approve not allowed");
    }

    /**
     * @notice getApproved is disabled because the nft is a sbt and cannot be transferred
     */
    function getApproved(
        uint256 tokenId
    ) public pure override(ERC721, IERC721) returns (address operator) {
        revert("SBT: getApproved not allowed");
    }

    /**
     * @notice setApprovalForAll is disabled because the nft is a sbt and cannot be transferred
     */
    function setApprovalForAll(
        address operator,
        bool _approved
    ) public pure override(ERC721, IERC721) {
        revert("SBT: setApprovalForAll not allowed");
    }

    /**
     * @notice isApprovedForAll is disabled because the nft is a sbt and cannot be transferred -> the output will always be false
     */
    function isApprovedForAll(
        address owner,
        address operator
    ) public pure override(ERC721, IERC721) returns (bool) {
        return false;
    }


    /** 
     * @notice Mint an SBT
     *
     * The sbt is minted to msg.sender
     * If the verification of the signature is okay see (https://github.com/Cypher-Laboratory/EVM-Verifier/issues/3) and :
     * - If mintStatus[proofId] == UNKNOWN, the proof is minted and the status is set to MINTED
     * - If mintStatus[proofId] == MINTED, the proof has already been minted. Tx will revert
     *
     * @param token - the erc20 address of the token we are proving the ownership of
     * @param minBalance - the balance threshold
     * @param uri - the IPFS uri
     * @param proofId - the hash of all the responses used in the proof
     * @param message - the hash of the message signed by the ring
     * @param ring - the ring of public keys
     * @param responses - the reponses of the ring
     * @param c - the signature c value
     */
    /*function mint( // TODO: comment on verifie que le message est bien valide -> le former dans le contrat
        address token,
        uint256 minBalance,
        string memory uri,
        string memory proofId,
        // signature data:
        string memory message, // should be keccack256 hash of message
        uint256[] memory ring, // ring of public keys [pkX1, pkY1, pkX2, pkY2, ..., pkXn, pkYn]
        uint256[] memory responses,
        uint256 c
    ) public payable returns (bool){
        if (mintStatus[proofId] == Status.MINTED) {
            revert AlreadyMinted(proofId);
        }

        if (!verifier.verifyRingSignature(message, ring, responses, c)) {
            revert InvalidSignature();
        }
        // if (!verifyTokenAmounts(token, minBalance, signature)) { // TODO: use chainlink api callto verify btc amounts
        //     revert InvalidTokenAmounts();
        // }
        mintStatus[proofId] = Status.MINTED;
        _safeMint(msg.sender, _nextTokenId);
        _setTokenURI(_nextTokenId, uri);
        _nextTokenId++;

        return true;
    }*/

    /**
     * @notice delete all the caracteristics of tokenId (burn)
     *
     * Only the owner of an sbt can burn it
     *
     * @param tokenId is the id of the sbt to burn
     */
    function burn(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) {
            revert OnlyOwnerCanBurn(tokenId);
        }
        _burn(tokenId);
    }

    
    function sendRequest(
    string calldata source,
    FunctionsRequest.Location secretsLocation,
    bytes calldata encryptedSecretsReference,
    string[] calldata args,
    bytes[] calldata bytesArgs,
    //mint data
    string memory uri,
    //signature data
    SignatureData calldata data
  ) external returns (bytes32){
     if (!verifier.verifyRingSignature(data.message, data.ring, data.responses, data.c)) {
            revert InvalidSignature();
        }
    FunctionsRequest.Request memory req;
    req.initializeRequest(FunctionsRequest.Location.Inline, FunctionsRequest.CodeLanguage.JavaScript, source);
    req.secretsLocation = secretsLocation;
    req.encryptedSecretsReference = encryptedSecretsReference;
    if (args.length > 0) {
      req.setArgs(args);
    }
    if (bytesArgs.length > 0) {
      req.setBytesArgs(bytesArgs);
    }
    s_lastRequestId = _sendRequest(req.encodeCBOR(), 1573, gaslimit, donId);
    requestToSender[s_lastRequestId]=msg.sender;
    requestToURI[s_lastRequestId]=uri;
    return s_lastRequestId;
  }

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastResponse = response;
        s_lastError = err;
        if (keccak256(s_lastResponse) == keccak256(abi.encodePacked(uint256(1)))){
             _safeMint(requestToSender[s_lastRequestId], _nextTokenId);
            _setTokenURI(_nextTokenId, requestToURI[s_lastRequestId]);
            _nextTokenId++;
        }
         emit Response(requestId, s_lastResponse, s_lastError);
    }
    // Override the _burn function from ERC721
    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
    }
}
