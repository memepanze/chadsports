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
import "./openzeppelin/Ownable.sol";
import "./openzeppelin/Strings.sol";
import "./openzeppelin/ReentrancyGuard.sol";

// Chainlink
import "./chainlink-vrf/VRFCoordinatorV2Interface.sol";
import "./chainlink-vrf/VRFConsumerBaseV2.sol";

// Utils functions
import "./Utils.sol";

/// @title Chad Sports Raffle.
/// @author Memepanze
/** @notice The goal of the Raffle contract is to store the addresses of the minters and select randomly 12 winners.
* The Raffle contract is call by the minting contract to index minters
* The Raffle contract contains two indexes: firstMinters and lastMinters
* - firstMinters: the first 500 addresses that mint from the Minting Contract
* - lastMinters: the addresses over the first 500 that mint from the Minting Contract
* To select winners we leverage on Chainlink VRF
* We select randomly 6 winners from the firstMinters index and 6 from the lastMinters index
* The firstMintersWinners will share 80% of the Raffle Pot
* The lastMintersWinners will share 20% of the Raffle Pot
*/
contract Raffle is VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // vrf coordinator {addres} Avalanche Fuji 0x2eD832Ba664535e5886b75D64C46EB9a228C2610
    // vrf coordinator {addres} Avalanche Mainnet 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634
    // vrf coordinator {addres} Ethereum Goerli 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D 
    // vrf coordinator {addres} Ethereum Mainnet 0x271682DEB8C4E0901D1a1550aD2e64D568E69909
    constructor(uint64 _vrfSubId, address _vrfCoordinator, bytes32 _keyHash, uint _cap, uint32 _nbrWinners) VRFConsumerBaseV2(_vrfCoordinator)
    {
        firstMintersCap = _cap;
        numberOfWinners = _nbrWinners;

        // Avalanche Fuji 0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61
        // Avalanche Mainnet 0xff8dedfbfa60af186cf3c830acbc32c05aae823045ae5ea7da1e45fbfaba4f92
        // Ethereum Goerli 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
        // Ethereum Mainnet 0x89630569c9567e43c4fe7b1633258df9f2531b62f2352fa721cf3162ee4ecb46
        keyHash = _keyHash;
        s_subscriptionId = _vrfSubId;
    }

    /// @notice The address of the NFT minting contract
    address public mintContract;

    /// @notice The number of unique minters
    uint public mintersCount;

    /// @notice The firstMinters limit count
    uint public firstMintersCap;

    /// @notice The number of the first minters /500
    uint public firstMintersCount;

    /// @notice The number of the last minters over the first 500 minters
    uint public lastMintersCount;

    /// @notice Check if the address of the minter is already in the index
    mapping(address => bool) public isAddressStored;

    /// @notice Index of the first 500 minters
    mapping(uint => address) public firstMinters;

    /// @notice Index of last minters
    mapping(uint => address) public lastMinters;

    /// @notice Number of winners of the Raffle
    uint32 public numberOfWinners;

    /// @notice The list of randomly selected winners from the first 500 minters.
    address[] public firstMintersWinners;

    /// @notice The list of randomly selected winners from the over first 500 minters.
    address[] public lastMintersWinners;

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
    bytes32 keyHash = 0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61;

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

    /// @notice Set the limit cap of the firstMinters count. Only the owner of the contract can call this function.
    function setFirstMintersCap(uint _cap) external onlyOwner {
        firstMintersCap = _cap;
    }

    /// @notice Set the minter address in the index and increment the minters count.
    function incrementMinters(address _minter) external onlyMintContract {
        if(!isAddressStored[_minter]){
            if(firstMintersCount < firstMintersCap){
                firstMinters[firstMintersCount] = _minter;
                firstMintersCount++;
            } else {
                lastMinters[lastMintersCount] = _minter;
                lastMintersCount++;
            }
            mintersCount++;
            isAddressStored[_minter] = true;
        }
    }

    // V R F

    /// @notice Admin function to change the VRF subscription ID
    function changeSubscription(uint64 _sub) external onlyOwner {
        s_subscriptionId = _sub;
    }

    /// @notice Request random numbers from the VRF and call the fulfillRandomWords.
    function randomWinners() external onlyOwner returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = VRFCoordinatorV2Interface(0x2eD832Ba664535e5886b75D64C46EB9a228C2610).requestRandomWords(
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
        uint[] memory firstArr = new uint[](numberOfWinners/2);
        uint[] memory lastArr = new uint[](numberOfWinners/2);

        for(uint i; i < _randomWords.length; i++){
            if(i < numberOfWinners/2){
                // Check if the index picked with the VRF is unique
                uint j;
                while(Utils.indexOf(firstArr, ((_randomWords[i] % (firstMintersCount-j)))) > -1){
                        j++;
                    }
                uint randNum = _randomWords[i] % (firstMintersCount-j);
                firstArr[i] = randNum;
                firstMintersWinners.push(firstMinters[firstArr[i]]);
            } else {
                if(mintersCount > firstMintersCap){
                    // Check if the index picked with the VRF is unique
                    uint j;
                    while(Utils.indexOf(lastArr, ((_randomWords[i] % (lastMintersCount-j)))) > -1){
                            j++;
                        }
                    uint randNum = _randomWords[i] % (lastMintersCount-j);
                    lastArr[i-numberOfWinners/2] = randNum;
                    lastMintersWinners.push(lastMinters[lastArr[i-numberOfWinners/2]]);
                }
            }
        }
        
        emit RequestFulfilled(_requestId, _randomWords);

    }
    
    /// @notice Reward the winners of the Raffle
    function rewardWinners() external onlyOwner {
        if(firstMintersWinners.length==0){
            revert Chad__NoWinners();
        }
        uint rafflePot = address(this).balance;
        if(rafflePot == 0){
            revert Chad__BalanceIsEmpty();
        }
        for(uint i; i < firstMintersWinners.length; i++){
            // 80% of the Raffle Pot will be transfer to the 6 winners (first 500 minters)
            bool sent;
            (sent, ) = firstMintersWinners[i].call{value:rafflePot*80/((numberOfWinners/2)*100)}("");
            if (!sent) {
                revert Chad__TransferFailed();
            }
        }
        for(uint i; i < lastMintersWinners.length; i++){
            // 20% of the Raffle Pot will be transfer to the 6 winners (over first 500 minters)
            bool sent;
            (sent, ) = lastMintersWinners[i].call{value:rafflePot*20/((numberOfWinners/2)*100)}("");
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
