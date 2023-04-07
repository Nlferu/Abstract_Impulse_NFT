// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error Abstract__NotEnoughETH();
error Abstract__TransferFailed();
error Abstract__FunctionDisabled();
error Abstract__NotExistingTokenId();
error Abstract__BidReceivedForThisNFT();
error Abstract__NoBidReceivedForThisNFT();
error Abstract__AddressIsNotHighestBidder();
error Abstract__AuctionFinishedForThisNFT();
error Abstract__AuctionStillOpenForThisNFT();
error Abstract__ContractOwnerIsNotAllowedToBid();

contract AbstractImpulseNFT is ERC721A, Ownable, ReentrancyGuard {
    // NFT Structs
    struct Auction {
        string s_tokenURIs;
        uint256 s_tokenIdToBid;
        address s_tokenIdToBidder;
        uint256 s_tokenIdToAuctionStart;
    }

    // NFT Variables
    uint256 constant minBid = 0.01 ether;
    uint256 constant startPrice = 0.1 ether;
    uint256 constant auctionDuration = 30;

    // NFT Mappings
    mapping(uint256 => Auction) private auctions;
    mapping(address => uint256) private pendingReturns;

    // NFT Events
    event NFT_BidAccepted(uint256 indexed tokenId);
    event NFT_SetTokenURI(string uri, uint256 indexed tokenId);
    event NFT_Minted(address indexed minter, uint256 indexed tokenId);
    event NFT_AuctionExtended(uint256 indexed time, uint256 indexed tokenId);
    event NFT_WithdrawCompleted(uint256 indexed amount, bool indexed transfer);
    event NFT_AddedPendingBidsForWithdrawal(uint256 indexed bid, address indexed bidder);
    event NFT_BidPlaced(uint256 indexed amount, address indexed bidder, uint256 indexed tokenId);
    event NFT_PendingBidsWithdrawal(uint256 indexed bid, address indexed bidder, bool indexed transfer);

    constructor() ERC721A("Abstract Impulse", "AIN") {}

    function mintNFT(string memory externalTokenURI) external onlyOwner {
        uint256 newTokenId = totalSupply();
        Auction storage auction = auctions[newTokenId];

        _mint(msg.sender, 1);

        auction.s_tokenIdToBid = startPrice;
        auction.s_tokenURIs = externalTokenURI;
        auction.s_tokenIdToAuctionStart = block.timestamp;

        emit NFT_Minted(msg.sender, newTokenId);
        emit NFT_SetTokenURI(auction.s_tokenURIs, newTokenId);
    }

    /** @dev Instead of transferring money back to outbidded address, give them opportunity to withdraw money */
    function placeBid(uint256 tokenId) external payable nonReentrant {
        Auction storage auction = auctions[tokenId];
        // Make sure the contract owner cannot bid
        if (msg.sender == owner()) revert Abstract__ContractOwnerIsNotAllowedToBid();

        // Check if NFT exists
        if (!_exists(tokenId)) revert Abstract__NotExistingTokenId();

        // Check if the auction is still ongoing
        if ((auction.s_tokenIdToAuctionStart + auctionDuration) < block.timestamp) {
            revert Abstract__AuctionFinishedForThisNFT();
        }

        // Extend the auction by 5 minutes if it's close to ending
        if ((auction.s_tokenIdToAuctionStart + auctionDuration - block.timestamp) < 2 minutes) {
            auction.s_tokenIdToAuctionStart += 2 minutes;
            emit NFT_AuctionExtended(auction.s_tokenIdToAuctionStart + auctionDuration - block.timestamp, tokenId);
        }

        // If there were no previous bids
        if (auction.s_tokenIdToBidder == address(0)) {
            // Check if the bid amount is high enough
            if (msg.value < startPrice) {
                revert Abstract__NotEnoughETH();
            }
        }
        // If there were previous bids
        else {
            // Check if the bid amount is high enough
            if (msg.value < (auction.s_tokenIdToBid + minBid)) revert Abstract__NotEnoughETH();

            pendingReturns[auction.s_tokenIdToBidder] += auction.s_tokenIdToBid;
            emit NFT_AddedPendingBidsForWithdrawal(pendingReturns[auction.s_tokenIdToBidder], auction.s_tokenIdToBidder);
        }

        // Update the bid and bidder
        auction.s_tokenIdToBid = msg.value;
        auction.s_tokenIdToBidder = payable(msg.sender);
        emit NFT_BidPlaced(auction.s_tokenIdToBid, auction.s_tokenIdToBidder, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        Auction storage auction = auctions[tokenId];
        return auction.s_tokenURIs;
    }

    function approve(address to, uint256 tokenId) public payable override biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (to != auction.s_tokenIdToBidder) revert Abstract__AddressIsNotHighestBidder();

        super.approve(to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (to != auction.s_tokenIdToBidder) revert Abstract__AddressIsNotHighestBidder();

        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public payable override biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (to != auction.s_tokenIdToBidder) revert Abstract__AddressIsNotHighestBidder();

        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public payable override biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (to != auction.s_tokenIdToBidder) revert Abstract__AddressIsNotHighestBidder();

        super.safeTransferFrom(from, to, tokenId, _data);
    }

    // Function disabled!
    function setApprovalForAll(address /*operator*/, bool /*approved*/) public pure override {
        revert Abstract__FunctionDisabled();
    }

    /**
     * @dev This will occur once timer end or if owner decide to accept bid, so js script has to trigger it, but there is onlyOwner approval needed
     */
    function acceptBid(uint256 tokenId) external onlyOwner biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (!_exists(tokenId)) revert Abstract__NotExistingTokenId();
        if (auction.s_tokenIdToBidder == address(0)) revert Abstract__NoBidReceivedForThisNFT();

        withdrawMoney(tokenId);
        approve(auction.s_tokenIdToBidder, tokenId);
        emit NFT_BidAccepted(tokenId);
    }

    function withdrawPending() external payable nonReentrant {
        uint256 amount = pendingReturns[msg.sender];

        if (amount > 0) {
            pendingReturns[msg.sender] = 0;
        } else {
            revert Abstract__NotEnoughETH();
        }

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            pendingReturns[msg.sender] = amount;
            revert Abstract__TransferFailed();
        }

        emit NFT_PendingBidsWithdrawal(amount, msg.sender, success);
    }

    /**
     * @dev We are able to withdraw money from contract only for closed biddings
     * If we leave it as "private" we should remove all "if" and modifiers as acceptBid is checking those
     */
    function withdrawMoney(uint256 tokenId) private onlyOwner biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (!_exists(tokenId)) revert Abstract__NotExistingTokenId();
        if (auction.s_tokenIdToBidder == address(0)) revert Abstract__NoBidReceivedForThisNFT();

        (bool success, ) = msg.sender.call{value: auction.s_tokenIdToBid}("");
        if (!success) revert Abstract__TransferFailed();

        emit NFT_WithdrawCompleted(auction.s_tokenIdToBid, success);
    }

    /**
     * @dev Create Function To Withdraw Pending Bids If Not Claimed After 10 Days
     */
    function withdrawUnclaimedBids(address bidder) external onlyOwner {}

    function renewAuction(uint256 tokenId) external onlyOwner biddingStateCheck(tokenId) {
        Auction storage auction = auctions[tokenId];
        if (!_exists(tokenId)) revert Abstract__NotExistingTokenId();
        if (auction.s_tokenIdToBidder != address(0)) revert Abstract__BidReceivedForThisNFT();

        auction.s_tokenIdToAuctionStart = block.timestamp;

        emit NFT_AuctionExtended((auction.s_tokenIdToAuctionStart + auctionDuration - block.timestamp), tokenId);
    }

    modifier biddingStateCheck(uint256 tokenId) {
        Auction storage auction = auctions[tokenId];
        if ((auction.s_tokenIdToAuctionStart + auctionDuration) > block.timestamp) {
            revert Abstract__AuctionStillOpenForThisNFT();
        }
        _;
    }

    // Function to be deleted
    // function getLogic(uint256 tokenId) external view returns (bool) {
    //     Auction storage auction = auctions[tokenId];
    //     return auction.s_tokenIdToBidder == address(0);
    // }

    function getHighestBidder(uint256 tokenId) external view returns (address) {
        Auction storage auction = auctions[tokenId];
        return auction.s_tokenIdToBidder;
    }

    function getHighestBid(uint256 tokenId) external view returns (uint256) {
        Auction storage auction = auctions[tokenId];
        return auction.s_tokenIdToBid;
    }

    function getTime(uint256 tokenId) external view returns (uint256) {
        Auction storage auction = auctions[tokenId];
        if ((auction.s_tokenIdToAuctionStart + auctionDuration) < block.timestamp) {
            revert Abstract__AuctionFinishedForThisNFT();
        }

        return auction.s_tokenIdToAuctionStart + auctionDuration - block.timestamp;
    }

    function getPending(address bidder) external view returns (uint256) {
        return pendingReturns[bidder];
    }
}
