pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC2981.sol";

contract GenericERC721 is ERC721, ERC2981 {
    address private _recipient;

    constructor() ERC721("name", "symbol") {
		_setDefaultRoyalty(address(this), 5000);
	}

	function setRoyalties(address recipient, uint96 amount) public
	{
		_setDefaultRoyalty(recipient, amount);
	}

    function mint(address to, uint256 id) public {
        _safeMint(to, id);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}