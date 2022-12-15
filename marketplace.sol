// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./generic721.sol";
import "./IERC721Receiver.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./ERC2981.sol";

contract MarketPlace is Ownable, IERC721Receiver {
    using Address for address payable;

    struct sale {
        address contractAddress;
        address payable owner;
        uint256 id;
        uint256 price;
    }

    struct auction {
        sale data;
        uint256 startTime;
        uint256 duration;
        address bidder;
        uint256 bid;
    }

    struct offer {
        sale data;
        address buyer;
    }

    address public araToken;
    uint256 public marketPlaceFee;
    uint256 public waiver;

    uint256 _salesId;
    uint256 _auctionId;
    uint256 _offerId;
	address wallet;

    mapping(uint256 => sale) internal _sales;
    mapping(uint256 => auction) internal _auctions;
    mapping(uint256 => offer) internal _offer;

    /**
     * @param _ara Waiver token
     * @param _marketFee Seller fee
     * @param _waiver Amount of _ara needed to wave market fee
     */

    constructor(
        address _ara,
		address _wallet,
        uint256 _marketFee,
        uint256 _waiver
    ) {
        araToken = _ara;
        marketPlaceFee = _marketFee;
        _salesId = 1;
        _auctionId = 1;
        _offerId = 1;
        waiver = _waiver;
		wallet = _wallet;
    }

    function setARA(address _ara) external onlyOwner {
        araToken = _ara;
    }

    function setFee(uint256 _marketFee) external onlyOwner {
        marketPlaceFee = _marketFee;
    }

    function setWaiver(uint256 _waiver) external onlyOwner {
        waiver = _waiver;
    }

    function setWallet(address _wallet) external onlyOwner{
        wallet = _wallet;
    }

    event attachId(uint256 transactionId);

	// Returns price, nft id, nft address, nft owner
    function getSimpleSale(uint256 saleId) external view returns (uint256, uint256, address, address) {
        return (_sales[saleId].price, _sales[saleId].id, _sales[saleId].contractAddress, _sales[saleId].owner);
    }

	//Returns  highest bid, nft id, highest bidder, nft contract, nft owner
    function getAuction(uint256 auctionId)
        external
        view
        returns (uint256, uint256, address, address, address) {
        return (_auctions[auctionId].bid, _auctions[auctionId].data.id, _auctions[auctionId].bidder, _auctions[auctionId].data.contractAddress, _auctions[auctionId].data.owner );
    }

	//Returns price, nft id, nft address, owner, buyer
	function getPassive(uint256 offerId)
        external
        view
        returns (uint256, uint256, address, address, address) {
        return (_offer[offerId].data.price, _offer[offerId].data.id, _offer[offerId].data.contractAddress, _offer[offerId].data.owner, _offer[offerId].buyer);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function completeSale(
        sale memory data,
        address holder,
        address buyer
    ) internal {
        GenericERC721 nft = GenericERC721(data.contractAddress);
        ERC20 ARA = ERC20(araToken);
        address royaltyRecipient;
        uint256 amount;

        uint256 price = data.price;

        nft.safeTransferFrom(holder, buyer, data.id);

        if (nft.supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyRecipient, amount) = nft.royaltyInfo(data.id, price);
            require(amount < price, "Royalties higher than selling price");
            payable(royaltyRecipient).sendValue(amount);

            price -= amount;
        }

        if (ARA.balanceOf(data.owner) < waiver)
		{
            data.owner.sendValue(price - ((data.price * marketPlaceFee) / 100));
        	payable(wallet).sendValue((data.price * marketPlaceFee) / 100);
		}
        else
            data.owner.sendValue(price);
    }

    /**
     * @dev Put up an NFT for sale at a fixed price. Nft will move into escrow
     * @param nftContract The token contract
     * @param nftId The tokenId.
     * @param price Price
     * @return saleId The id of the sale that was created
     */
    function createSimpleOffer(
        address nftContract,
        uint256 nftId,
        uint256 price
    ) external returns (uint256) {
        GenericERC721 nft = GenericERC721(nftContract);

        nft.safeTransferFrom(msg.sender, address(this), nftId);
        _sales[_salesId] = sale(nftContract, payable(msg.sender), nftId, price);
        _salesId++;

        emit attachId(_salesId - 1);
        return _salesId - 1;
    }

    /**
     * @dev Removes an NFT from sale, NFT will be sent back to owner
     * @param saleId The sale to remove
     */

    function removeSimpleOffer(uint256 saleId) external {
        require(
            _sales[saleId].owner == msg.sender,
            "You are not the creator of this sale"
        );

        ERC721 nft = ERC721(_sales[saleId].contractAddress);

        nft.safeTransferFrom(address(this), msg.sender, _sales[saleId].id);
        delete _sales[saleId];
    }

    /**
     * @dev Updates an NFT sale with a new price
     * @param saleId The sale to update
     */
    function updateSimpleOffer(uint256 saleId, uint256 newPrice) external {
        require(
            _sales[saleId].owner == msg.sender,
            "You are not the creator of this sale"
        );

        _sales[saleId].price = newPrice;
    }

    /**
     * @dev Buy a NFT that was put for sale; The marketplace charges a fee to the seller unless
     * they own a sufficent amount of _ara. The nft will be transfered to the buyer and
     * the adjusted payment will be trasferred to the seller;
     * @param saleId The sale to buy
     */

    function buySimpleOffer(uint256 saleId) external payable {
        require(
            _sales[saleId].contractAddress != address(0x0),
            "This sale does not exist or has ended"
        );
        require(msg.value == _sales[saleId].price, "Insufficient funds");

        sale memory data = _sales[saleId];
        delete _sales[saleId];

        completeSale(data, address(this), msg.sender);
    }

    /**
     * @dev Updates an NFT sale with a new price
     * @param  nftContract The token contract
     * @param  nftId The token id
     * @param  price The minimum price to be met
     * @param  startTime The starting time of the auction (in epoch time)
     * @param  duration The duration of the sale (in seconds)
     */
    function createAuction(
        address nftContract,
        uint256 nftId,
        uint256 price,
        uint256 startTime,
        uint256 duration
    ) external returns (uint256) {
        ERC721 nft = ERC721(nftContract);

        nft.transferFrom(msg.sender, address(this), nftId);
        _auctions[_auctionId] = auction(
            sale(nftContract, payable(msg.sender), nftId, price),
            startTime,
            duration,
            address(0x0),
            0
        );

        _auctionId++;
        emit attachId(_auctionId - 1);
        return _auctionId - 1;
    }

    /**
     * @dev Bids on an auction. If the bid is higher than the current bid, refund the previoud bidder, and place the current bid in escrow
     * @param  auctionId Auction to bid on
     */
    function bidAuction(uint256 auctionId) external payable {
        require(
            _auctions[auctionId].data.owner != address(0x0),
            "Auction does not exist or has ended"
        );
        require(
            _auctions[auctionId].startTime <= block.timestamp,
            "Auction has not started"
        );
        require(
            block.timestamp <=
                (_auctions[auctionId].startTime +
                    _auctions[auctionId].duration),
            "Auction has ended"
        );
        require(
            msg.value > _auctions[auctionId].bid,
            "New bid should be higher than current one."
        );

        address bidder = _auctions[auctionId].bidder;
        uint256 amount = _auctions[auctionId].bid;

        _auctions[auctionId].bid = msg.value;
        _auctions[auctionId].bidder = msg.sender;

        if (bidder != address(0x0)) payable(bidder).sendValue(amount);
    }

    /**
     * @dev Highest bidder can redeem their nft if their bid macthes our outmatches the price set  by seller, and if the auction has ended
     *  The marketplace charges a fee to the seller unless
     * they own a sufficent amount of _ara. The nft will be transfered to the bidder and
     * the adjusted payment will be trasferred to the seller;
     * @param  auctionId Auction to bid on
     */
    function redeemAuction(uint256 auctionId) external {
        require(
            _auctions[auctionId].data.owner != address(0x0),
            "Auction does not exist or has ended"
        );
        require(
            block.timestamp >=
                (_auctions[auctionId].startTime +
                    _auctions[auctionId].duration),
            "Auction still in progress"
        );
        require(
            msg.sender == _auctions[auctionId].bidder,
            "Only highest bidder can redeem NFT"
        );
        require(
            _auctions[auctionId].bid >= _auctions[auctionId].data.price,
            "Highest bid is lower than asking price"
        );

        _auctions[auctionId].data.price = _auctions[auctionId].bid;

		sale memory data = _auctions[auctionId].data;
        address bidder = _auctions[auctionId].bidder;
        delete _auctions[auctionId];

        completeSale(
            data,
            address(this),
            bidder
        );
    }

	function endAuction(uint256 auctionId) external
	{
		require(
            _auctions[auctionId].data.owner != address(0x0),
            "Auction does not exist"
        );
		require(_auctions[auctionId].data.owner == msg.sender ||
            _auctions[auctionId].bidder == msg.sender ||
            owner() == msg.sender
            , "Only nft owner, contract owner or bidder can end the auction");
        require(
            block.timestamp >=
                (_auctions[auctionId].startTime +
                    _auctions[auctionId].duration),
            "Auction still in progress"
        );
        require(
            _auctions[auctionId].bid < _auctions[auctionId].data.price,
            "Cannot end auction whose bid has met the asking price"
        );

		ERC721 nft = ERC721(_auctions[auctionId].data.contractAddress);
        uint256 bid = _auctions[auctionId].bid;
        address bidder = _auctions[auctionId].bidder;

		nft.transferFrom(address(this), _auctions[auctionId].data.owner, _auctions[auctionId].data.id);
		delete _auctions[auctionId];

		payable(bidder).sendValue(bid);

	}

    /**
     * @dev User makes an offer to buy an nft. The funds are moved into escrow
     * @param  nftContract The token contract
     * @param  nftId The token id
     * @param  price Offering price
     */
    function createPassiveOffer(
        address nftContract,
        uint256 nftId,
        uint256 price
    ) external payable returns (uint256) {
        ERC721 nft = ERC721(nftContract);

        require(price == msg.value, "Insufficient funds");
        _offer[_offerId] = offer(
            sale(nftContract, payable(nft.ownerOf(nftId)), nftId, price),
            msg.sender
        );
        _offerId++;

        emit attachId(_offerId - 1);
        return _offerId - 1;
    }

    /**
     * @dev Nft owner rejects the offer. Funds go back to offerer
     * @param  offerId Offer id
     */
    function rejectOffer(uint256 offerId) external {
        require(
            _offer[offerId].data.owner != address(0x0),
            "Offer does not exist or has ended"
        );

        ERC721 nft = ERC721(_offer[offerId].data.contractAddress);

        require(
            msg.sender == nft.ownerOf(_offer[offerId].data.id),
            "Only nft owner can cancel offer"
        );

        uint256 price = _offer[offerId].data.price;
        address buyer = _offer[offerId].buyer;

        delete _offer[offerId];

        payable(buyer).sendValue(price);
    }

    /**
     * @dev Nft owner accepts the offer. Funds are transferred to the nft owner, nft is trasnferred to offerer
     *  The marketplace charges a fee to the seller unless
     * they own a sufficent amount of _ara. The nft will be transfered to the bidder and
     * the adjusted payment will be trasferred to the seller;
     * @param  offerId Offer id
     */
    function acceptOffer(uint256 offerId) external {
        require(
            _offer[offerId].data.owner != address(0x0),
            "Offer does not exist or has ended"
        );

        ERC721 nft = ERC721(_offer[offerId].data.contractAddress);

        address owner = nft.ownerOf(_offer[offerId].data.id);

        require(msg.sender == owner, "Only nft owner can accept offer");

        sale memory data =  _offer[offerId].data;
        address buyer = _offer[offerId].buyer;

        data.owner = payable(owner);
        delete _offer[offerId];

        completeSale(data, owner, buyer);
    }

    /**
     * @dev Cancel offer. Funds are sent back to offerrer;
     * @param  offerId Offer id
     */
    function cancelOffer(uint256 offerId) external {
        require(
            _offer[offerId].data.owner != address(0x0),
            "Offer does not exist or has ended"
        );

        require(
            msg.sender == _offer[offerId].buyer,
            "Only offer creator can cancel offer"
        );
        uint256 price = _offer[offerId].data.price;
        delete _offer[offerId];

        payable(msg.sender).sendValue(price);
    }
}