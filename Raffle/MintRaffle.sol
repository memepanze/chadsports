// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**

  ________              __   _____                  __      
  / ____/ /_  ____ _____/ /  / ___/____  ____  _____/ /______
 / /   / __ \/ __ `/ __  /   \__ \/ __ \/ __ \/ ___/ __/ ___/
/ /___/ / / / /_/ / /_/ /   ___/ / /_/ / /_/ / /  / /_(__  ) 
\____/_/ /_/\__,_/\__,_/   /____/ .___/\____/_/   \__/____/  
                               /_/                           


*/

// OpenZeppelin
import "../openzeppelin/ERC1155.sol";
import "../openzeppelin/ERC1155Supply.sol";
import "../openzeppelin/IERC2981.sol";
import "../openzeppelin/Ownable.sol";
import "../openzeppelin/Strings.sol";
import "../openzeppelin/ReentrancyGuard.sol";

// Raffle
import "../IRaffle.sol";

// Utils functions
import "../Utils.sol";

/// @title Chad Sports Minting.
/// @author Memepanze
/** @notice ERC1155 Minting contract for Chad Sports.
* - Minting: The contract allows to mint specific Teams (1 or 4 ERC1155 tokenId(s)) or to mint randomly Teams (1 or 4 ERC1155 tokenId(s))
* - The randomness is powered by Chainlink VRF.
* There is no maximum supply, however the minting period is 24h.
* - Discount: There are two types of Discount Price: normal discount and Chad discount.
* -- Normal Discount: For that feature we will allow the holders addresses of collection that we partner with + addresses that participate to the whitelisting process on social media and website.
* -- Normal Discount benefits: a discount price to mint Teams during the minting period.
* -- Chad Discount: Only the 32 hodlers of the unique Chad collection (1:1) can be part of the ChadList
* -- Chad Discount Benefits: The 32 hodlers can freemint 4 teams of their choice only one time.
*/

contract ChadMintRaffle is ERC1155, ERC1155Supply, IERC2981, ReentrancyGuard, Ownable {
    using Strings for uint256;

    constructor() ERC1155("")
        {
        name = "Chad Raffle";
        symbol = "CHADRAF";
        _uriBase = "ipfs://bafybeia3m4w3xcif7bs3g35mgphgnwrouguny36so6f57hziw3gobstpty/"; // IPFS base for ChadSports collection

        mintPrice = 0.25 ether;
    }

    /// @notice The Name of collection 
    string public name;
    /// @notice The Symbol of collection 
    string public symbol;
    /// @notice The URI Base for the metadata of the collection 
    string public _uriBase;

    /// @notice The start date for the minting
    /// @dev for the 2022 world cup 1668877200
    uint public startDate;

    /// @notice The end date for the minting
    /// @dev for the 2022 world cup 1668952800
    uint public endDate;

    /// @notice The address of the Raffle contract 
    address public raffle;

    /// @notice royalties recipient address
    address public _recipient;

    /// @notice The standard mint price for single specific mint
    uint internal mintPrice;

    /// @notice Emitted on withdrawBalance() 
    event BalanceWithdraw(address to, uint amount);

    // E R R O R S

    error Chad__Unauthorized();

    error Chad__NotInTheMitingPeriod();

    error Chad__TransferFailed();

    // M O D I F I E R S
    
    /// @notice Check if the minter is an externally owned account
    modifier isEOA() {
        if (tx.origin != msg.sender) {
            revert Chad__Unauthorized();
        }
        _;
    }

    /**
    * @dev Modifier to set the minting price for the specific mint functions
    * @param _count The number of tickets to mint
    */
    modifier payableMint(uint _count) {
        require(block.timestamp >= startDate && block.timestamp <= endDate);
        if(_count > 1){
            require(msg.value >= mintPrice*_count);
        } else {
            require(msg.value >= mintPrice);
        }
        _;
    }

    /// @notice Set the start date (timestamp) for the minting.
    function setStartDate(uint _date) external onlyOwner {
        startDate = _date;
    }

    /// @notice Set the end date (timestamp) for the minting.
    function setEndDate(uint _date) external onlyOwner {
        endDate = _date;
    }

    /// @notice Set the new base URI for the collection.
    function setUriBase(string memory _newUriBase) external onlyOwner {
        _uriBase = _newUriBase;
    }

    /// @notice URI override for OpenSea traits compatibility.
    function uri(uint256 tokenId) override public view returns (string memory) {
        return string(abi.encodePacked(_uriBase, tokenId.toString(), ".json"));
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /// @notice Set the Raffle contract address.
    function setRaffleContract(address _addr) external onlyOwner {
        raffle = _addr;
    }

    // M I N T

    /// @notice Mint specific tokenIDs.
    /// @param _count the number of tickets to mint.
    /// @dev the array must contain 1 or 4 values
    /// @dev the tokenIds are from 1 to 32
    function mint(uint _count) public payable nonReentrant isEOA
        payableMint(_count) 
        {
        if(_count > 1){
            
            uint[] memory _ids = new uint[](_count);
            uint[] memory amount = new uint[](_count);
            for(uint _i = 0; _i < _count ; _i++){
                _ids[_i]= 0;
                amount[_i] = 1;
            }
            

            _mintBatch(msg.sender, _ids, amount, "");
        } else {
            _mint(msg.sender, 0, 1, "");
        }
        // IRaffle(raffle).incrementMinters(msg.sender);
    }

    /// @notice Withdraw the contract balance to the contract owner
    /// @param _to Recipient of the withdrawal
    function withdrawBalance(address _to) external onlyOwner nonReentrant {
        uint amount = address(this).balance;
        bool sent;

        (sent, ) = _to.call{value: amount}("");
        if (!sent) {
            revert Chad__TransferFailed();
        }

        emit BalanceWithdraw(_to, amount);
    }

    // R O Y A L T I E S

    /// @dev Royalties implementation.

    /**
     * @dev EIP2981 royalties implementation: set the recepient of the royalties fee to 'newRecepient'
     * Maintain flexibility to modify royalties recipient (could also add basis points).
     *
     * Requirements:
     *
     * - `newRecepient` cannot be the zero address.
     */

    function _setRoyalties(address newRecipient) internal {
        require(newRecipient != address(0));
        _recipient = newRecipient;
    }

    function setRoyalties(address newRecipient) external onlyOwner {
        _setRoyalties(newRecipient);
    }

    // EIP2981 standard royalties return.
    function royaltyInfo(uint256 _salePrice) external view override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (_recipient, (_salePrice * 6) / 100);
    }

    // EIP2981 standard Interface return. Adds to ERC1155 and ERC165 Interface returns.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, IERC165)
        returns (bool)
    {
        return (
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId)
        );
    }
}