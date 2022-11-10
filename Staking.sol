// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// OpenZeppelin
import "./openzeppelin/IERC1155.sol";
import "./openzeppelin/IERC1155Receiver.sol";
import "./openzeppelin/Ownable.sol";
import "./openzeppelin/ReentrancyGuard.sol";

// Utils functions
import "./Utils.sol";

/// @title Chad Sports Staking.
/// @author Memepanze
/// @notice ERC1155 Staking contract for Chad Sports to rank the teams and get rewarded.
contract ChadStaking is Ownable, ReentrancyGuard {

    /// @notice ERC1155 interface variable
    IERC1155 public nft;

    /// @notice map each address to a submissionId {uint} and inside of each: map a rank {uint} to a teamId {uint}
    mapping (address => mapping(uint => mapping(uint => uint) )) public submission;

    /// @notice 
    mapping(address => uint) public submissionCount;

    /// @notice
    mapping(uint => mapping(address => uint)) public nftOwners;

    /// @notice an array of the final ranking of the 4 teams in the World Cup
    uint[4] public finalRanking;

    /// @notice Check if the Final Ranking is set by contract owners after the World Cup if finished
    bool public isFinalRankingSet;

    /// @notice List of winners
    address[] public winners;

    // M O D I F I E R

    /// @notice NFTs hodlers can change their rankings until 1 hour before the Top 16
    modifier changeRankings {
        require(block.timestamp <= 1670594400);
        _;
    }

    constructor(address _nft) {
        nft = IERC1155(_nft);
    }

    /// @notice User stake batch 4 teams (ERC1155) by ranking the NFTs from 1 to 4.
    /// @dev This function can be called before the start of the Top 16 of the world cup.
    function stakeBatch(uint8 _rank1, uint8 _rank2, uint8 _rank3, uint8 _rank4) external nonReentrant changeRankings {

        // track of the number of submissions by address
        uint subId = submissionCount[msg.sender];
        submission[msg.sender][subId][1] = _rank1;
        submission[msg.sender][subId][2] = _rank2;
        submission[msg.sender][subId][3] = _rank3;
        submission[msg.sender][subId][4] = _rank4;
        submissionCount[msg.sender]++;

        uint[] memory ids = new uint[](4);
        ids[0] = _rank1;
        ids[1] = _rank2;
        ids[2] = _rank3;
        ids[3] = _rank4;
        uint[] memory amounts = new uint[](4);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;

        // The ERC1155 are transfer to the contract address to avoid user to have multiple ranking with the same NFTs
        nft.safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "");

        // Track of the ownership of the NFTs which will be used to allow the user to unstake its staked ERC1155.
        nftOwners[_rank1][msg.sender]++;
        nftOwners[_rank2][msg.sender]++;
        nftOwners[_rank3][msg.sender]++;
        nftOwners[_rank4][msg.sender]++;
    }

    /// @notice User unstakes batch its 4 teams (ERC1155).
    function unstakeBatch(uint256 _submissionId) external nonReentrant {
        require(nftOwners[submission[msg.sender][_submissionId][1]][msg.sender]>0, "#1 Not your NFT");
        require(nftOwners[submission[msg.sender][_submissionId][2]][msg.sender]>0, "#2 Not your NFT");
        require(nftOwners[submission[msg.sender][_submissionId][3]][msg.sender]>0, "#3 Not your NFT");
        require(nftOwners[submission[msg.sender][_submissionId][4]][msg.sender]>0, "#4 Not your NFT");
        

        uint[] memory ids = new uint[](4);
        ids[0] = submission[msg.sender][_submissionId][1];
        ids[1] = submission[msg.sender][_submissionId][2];
        ids[2] = submission[msg.sender][_submissionId][3];
        ids[3] = submission[msg.sender][_submissionId][4];
        uint[] memory amounts = new uint[](4);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;

        delete submission[msg.sender][_submissionId][1];
        delete submission[msg.sender][_submissionId][2];
        delete submission[msg.sender][_submissionId][3];
        delete submission[msg.sender][_submissionId][4];

        nft.safeBatchTransferFrom(address(this), msg.sender, ids, amounts, "");
    }

    // R E W A R D

    /// @notice Check if a ranking submission is winning.
    function isWinner(uint _submissionId) external {
        require(isFinalRankingSet, "Final Ranking Not Set");
        require(submission[msg.sender][_submissionId][1] == finalRanking[0], "Not eligible");
        require(submission[msg.sender][_submissionId][2] == finalRanking[1], "Not eligible");
        require(submission[msg.sender][_submissionId][3] == finalRanking[2], "Not eligible");
        require(submission[msg.sender][_submissionId][4] == finalRanking[3], "Not eligible");
        
        winners.push(msg.sender);
    }

    /// @notice Admin function to set the final ranking of the Top 4 for the World Cup.
    function setFinalRanking(uint _1, uint _2, uint _3, uint _4) public onlyOwner {
        finalRanking[0] = _1;
        finalRanking[1] = _2;
        finalRanking[2] = _3;
        finalRanking[3] = _4;
        isFinalRankingSet = true;
    }

    /// @notice Admin function to reward the list of Winners
    function rewardWinners() public payable onlyOwner {
        for(uint i; i < winners.length; i++){
            payable(address(winners[i])).transfer(address(this).balance*50/100*winners.length);
        }
    }


    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

}