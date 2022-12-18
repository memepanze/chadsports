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
import "../openzeppelin/Ownable.sol";
import "../openzeppelin/Strings.sol";
import "../openzeppelin/ReentrancyGuard.sol";

// Chainlink
import "../chainlink-vrf/VRFCoordinatorV2Interface.sol";
import "../chainlink-vrf/VRFConsumerBaseV2.sol";

// Utils functions
import "../Utils.sol";

/// @title Chad Sports Raffle.
/// @author Memepanze
/** @notice The goal of the Raffle contract is to store the addresses of the minters and select randomly 12 winners.
* The Raffle contract is call by the minting contract to index minters
* The Raffle contract contains two indexes: wallets and tickets
* - wallets: the addresses that mint from the Minting Contract
* - tickets: the index of tickets minted from the Minting Contract and mapped with a wallet
* Every 150 wallets the contract increments the number of winners by 1
* To select winners we leverage on Chainlink VRF
* We select randomly {3 + (1* sum(wallets-150)/150)} winners from the tickets index mapped to a wallet
* The firstMintersWinners will share 80% of the Raffle Pot
* The lastMintersWinners will share 20% of the Raffle Pot
*/
contract Raffle is VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // vrf coordinator {addres} Avalanche Fuji 0x2eD832Ba664535e5886b75D64C46EB9a228C2610
    // vrf coordinator {addres} Avalanche Mainnet 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634
    constructor(uint64 _vrfSubId, address _vrfCoordinator, bytes32 _keyHash, uint _range, uint32 _nbrWinners) VRFConsumerBaseV2(_vrfCoordinator)
    {
        walletsRange = _range;
        numberOfWinners = _nbrWinners;

        // Avalanche Fuji 0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61
        // Avalanche Mainnet 0x89630569c9567e43c4fe7b1633258df9f2531b62f2352fa721cf3162ee4ecb46
        keyHash = _keyHash;
        s_subscriptionId = _vrfSubId;
        vrfCoordinator = _vrfCoordinator;
    }

    /// @notice The address of the NFT minting contract
    address public mintContract;

    /// @notice The number of unique walletss
    uint public walletsCount;

    /// @notice The number of unique tickets
    uint public ticketsCount;

    /// @notice The number of wallets after each the contract increment the number of winners
    uint public walletsRange;

    /// @notice The number of range to calculate the number of winners, after each 150 wallets minters, the currentRange increments
    uint private currentRange = 1;

    /// @notice Check if the address of the minter is already in the index
    mapping(address => bool) public isAddressStored;

    /// @notice Index of the wallets
    mapping(uint => address) public walletsIndex;

    /// @notice Index of the tickets
    mapping(uint => address) public ticketsIndex;

    /// @notice Number of winners of the Raffle
    uint32 public numberOfWinners;

    /// @notice The list of randomly selected winners .
    address[] public winners;

    /// @notice The vrf coordinator address
    address vrfCoordinator;

    /// @notice The struct used for the VRF requests
    struct RequestStatus {
        address sender; // msg.sender of the request
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
    }

    /// @notice The request status for each request ID (Chainlink VRF)
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    // VRFCoordinatorV2Interface COORDINATOR;

    /// @notice The subscription ID (Chainlink VRF)
    uint64 s_subscriptionId;

    /// @notice The past resquests Id (Chainlink VRF)
    uint256[] public requestIds;
    /// @notice The last resquest Id (Chainlink VRF)
    uint256 public lastRequestId;

    /** @notice The gas lane to use, which specifies the maximum gas price to bump to.
      * For a list of available gas lanes on each network,
      * see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
      */
    bytes32 keyHash;

    /** @notice Depends on the number of requested values that you want sent to the
      * fulfillRandomWords() function. Storing each word costs about 20,000 gas,
      * so 100,000 is a safe default for this example contract. Test and adjust
      * this limit based on the network that you select, the size of the request,
      * and the processing of the callback request in the fulfillRandomWords()
      * function.
      */
    uint32 callbackGasLimit = 1000000;

    /// @notice The number of block confirmation, the default is 3, but it can be set this higher.
    uint16 requestConfirmations = 3;

    /// @notice The number of random numbers to request. 
    /// @dev Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = numberOfWinners;

    /// @notice check if the call is the mint contract
    modifier onlyMintContract {
        require(msg.sender == mintContract);
        _;
    }

    // E R R O R S

    error Chad__TransferFailed();

    error Chad__BalanceIsEmpty();

    error Chad__NoWinners();

    // E V E N T S

    /// @notice Emitted on the receive()
    /// @param amount The amount of received Eth
    event ReceivedEth(uint amount);

    /// @notice Emitted on withdrawBalance() 
    event BalanceWithdraw(address to, uint amount);

    /// @notice Emitted on mintRandom()
    /// @param requestId The request id for the VRF request
    /// @param numWords number of random numbers requested
    event RequestSent(uint256 requestId, uint32 numWords);
    /// @notice Emitted on fulfillRandomWords()
    /// @param requestId The request id for the VRF fulfilled request
    /// @param randomWords number of random numbers requested
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    /// @notice Set the address of the minting contract. Only the owner of the contract can call this function.
    function setMintContract(address _contract) external onlyOwner {
        mintContract = _contract;
    }

    /// @notice Set the number of wallets after each the contract increment the number of winners.
    function setWalletsRange(uint _range) external onlyOwner {
        walletsRange = _range;
    }

    /// @notice Set the minter address in the index and increment the minters count.
    function incrementMinters(address _minter, uint _count) external onlyMintContract {
        if(!isAddressStored[_minter]){
            if(walletsCount >= walletsRange*currentRange){
                currentRange++;
                numberOfWinners++;
            }
            walletsIndex[walletsCount] = _minter;
            walletsCount++;
            isAddressStored[_minter] = true;
        }
        for(uint i = 0; i < _count; i++){
            ticketsIndex[ticketsCount+i] = _minter;
        }
        ticketsCount += _count;
    }

    // V R F

    /// @notice Admin function to change the VRF subscription ID
    function changeSubscriptionVRF(uint64 _sub) external onlyOwner {
        s_subscriptionId = _sub;
    }

    /// @notice Request random numbers from the VRF and call the fulfillRandomWords.
    function randomWinners() external onlyOwner returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = VRFCoordinatorV2Interface(vrfCoordinator).requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numberOfWinners
        );
        s_requests[requestId] = RequestStatus({exists: true, fulfilled: false, sender: msg.sender});
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numberOfWinners);
        return requestId;
    }

    /**
    * @notice Callback function called by the Chainlink Oracle with the array 
    * containing the random numbers to pick winners for the Raffle.
    * @dev if the number of minters is lower than 500, the contract will only push 6 unique winners.
    */
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(s_requests[_requestId].exists);
        // Arrays to store the indexes picked by the VRF in order to make checks to be sure we end up with unique addresses for the winners
        uint[] memory winArr = new uint[](numberOfWinners);

        for(uint i; i < _randomWords.length; i++){
            // Check if the index picked with the VRF is unique
            uint j;
            while(Utils.indexOf(winArr, ((_randomWords[i] % (ticketsCount-j)))) > -1){
                    j++;
                }
            uint randNum = _randomWords[i] % (ticketsCount-j);
            winArr[i] = randNum;
            winners.push(ticketsIndex[winArr[i]]);
        }
        
        emit RequestFulfilled(_requestId, _randomWords);

    }
    
    /// @notice Reward the winners of the Raffle
    function rewardWinners() external onlyOwner {
        if(winners.length==0){
            revert Chad__NoWinners();
        }
        uint rafflePot = address(this).balance;
        if(rafflePot == 0){
            revert Chad__BalanceIsEmpty();
        }
        for(uint i; i < winners.length; i++){
            // 80% of the Raffle Pot will be transfer to the 6 winners (first 500 minters)
            bool sent;
            (sent, ) = winners[i].call{value:rafflePot/(numberOfWinners*100)}("");
            if (!sent) {
                revert Chad__TransferFailed();
            }
        }
    }

    /// @notice The Raffle contract will receive the rewards from the Minting Contract.
    receive() external payable {
        emit ReceivedEth(msg.value);
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
}
