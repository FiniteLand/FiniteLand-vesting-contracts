// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct VestingRound {
        uint256 vestingUnlock1;
        uint256 vestingUnlock2;
        uint256 vestingPeriod;
        uint256 vestingPercent;
    }

    struct User {
        uint256 amount;
        uint256 claimed;
        uint256 roundID;
    }

    struct DataPrivateUser {
        address user;
        uint256 amount;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 constant precision = 10**20;

    /// @notice get token address
    IERC20 public immutable token;
    /// @notice get information about the round by id
    VestingRound[] public rounds;

    mapping(address => User) public users;

    event VestingRoundCreated(
        uint256 vestingUnlock1,
        uint256 vestingUnlock2,
        uint256 vestingPeriod,
        uint256 vestingPercent,
        uint256 indexed roundNum,
        uint256 timestamp
    );
    event TokensClaimed(
        uint256 amount,
        address indexed sender,
        uint256 timestamp
    );
    event AddPrivateUsers(
        DataPrivateUser[] dataUser,
        uint256 roundID,
        uint256 timestamp
    );

    constructor(address _token) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);

        token = IERC20(_token);
    }

    function createVestingRound(
        uint256 vestingUnlock1,
        uint256 vestingUnlock2,
        uint256 vestingPeriod,
        uint256 vestingPercent
    ) external onlyRole(ADMIN_ROLE) {
        require(vestingUnlock1 < vestingUnlock2, "Vesting DAO: bad timing");

        VestingRound memory vestingRound = VestingRound({
            vestingUnlock1: vestingUnlock1,
            vestingUnlock2: vestingUnlock2,
            vestingPeriod: vestingPeriod,
            vestingPercent: vestingPercent
        });

        rounds.push(vestingRound);

        emit VestingRoundCreated(
            vestingUnlock1,
            vestingUnlock2,
            vestingPeriod,
            vestingPercent,
            rounds.length - 1,
            block.timestamp
        );
    }

    /**
     *@dev add private users to whitelist; and assign amount to claim
     *@param dataUser array with user information
     *@param roundID round ID
     */
    function addPrivateUsers(
        DataPrivateUser[] calldata dataUser,
        uint256 roundID
    ) external onlyRole(ADMIN_ROLE) {
        require(
            roundID <= rounds.length - 1,
            "Vesting DAO: such a round does not exist"
        );
        for (uint256 i = 0; i < dataUser.length; i++) {
            require(
                users[dataUser[i].user].amount == 0 &&
                    users[dataUser[i].user].claimed == 0,
                "Vesting DAO: the user is already participating in one of the rounds"
            );
            users[dataUser[i].user].amount = dataUser[i].amount;
            users[dataUser[i].user].roundID = roundID;
        }
        emit AddPrivateUsers(dataUser, roundID, block.timestamp);
    }

    /**
     *@dev sends tokens from pool to user
     *@param account address user
     */
    function sendToUser(address account) external onlyRole(ADMIN_ROLE) {
        User storage user = users[account];

        uint256 availableAmount_ = user.amount - user.claimed;
        require(availableAmount_ > 0, "Vesting DAO: there is nothing to send");

        user.claimed += availableAmount_;
        IERC20(token).safeTransfer(account, availableAmount_);

        emit TokensClaimed(availableAmount_, account, block.timestamp);
    }

    /**
     *@dev withdraw tokens from the contract
     *@param amount amount tokens
     */
    function withdraw(uint256 amount, address tokenAddr) external onlyRole(ADMIN_ROLE) {
        IERC20(tokenAddr).safeTransfer(msg.sender, amount);
    }

    /**
     *@dev token deposit
     *@param amount amount tokens
     */
    function deposit(uint256 amount) external onlyRole(ADMIN_ROLE) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Claims available token
    function claim() external nonReentrant {
        User storage user = users[msg.sender];

        VestingRound memory vesting = rounds[user.roundID];

        require(
            block.timestamp > vesting.vestingUnlock1,
            "Vesting DAO: claim is not available yet"
        );

        uint256 availableAmount = calcAvailableAmount(msg.sender);
        require(
            availableAmount > 0,
            "Vesting DAO: there are not available tokens to claim"
        );

        user.claimed += availableAmount;
        IERC20(token).safeTransfer(msg.sender, availableAmount);

        emit TokensClaimed(availableAmount, msg.sender, block.timestamp);
    }

    /**
     *@dev get information about all rounds
     */
    function getInfoVestingRounds()
        external
        view
        returns (VestingRound[] memory)
    {
        return rounds;
    }

    /**
     *@dev get the number of rounds
     */
    function getRoundsNumber() external view returns (uint256) {
        return rounds.length;
    }

    /**
     *@dev will get information about the user
     *@param account address user
     *@return struct User
     *@return AvailableAmount
     */
    function getUserInfo(address account)
        external
        view
        returns (User memory, uint256)
    {
        return (users[account], calcAvailableAmount(account));
    }

    /**
     *@dev Calculates available token tokens to claim
     *@param account address user
     */
    function calcAvailableAmount(address account)
        public
        view
        returns (uint256)
    {
        User memory user = users[account];
        VestingRound memory vesting = rounds[user.roundID];
        if (user.amount == 0 || block.timestamp < vesting.vestingUnlock1)
            return 0;

        if (block.timestamp > vesting.vestingUnlock2 + vesting.vestingPeriod)
            return user.amount - user.claimed;
        uint256 availableAmount = (user.amount *
            (precision - vesting.vestingPercent)) / precision;
        if (
            block.timestamp >= vesting.vestingUnlock2 &&
            block.timestamp <= vesting.vestingUnlock2 + vesting.vestingPeriod
        ) {
            availableAmount +=
                ((user.amount - availableAmount) *
                    (block.timestamp - vesting.vestingUnlock2)) /
                vesting.vestingPeriod;
        }

        availableAmount -= user.claimed;

        return availableAmount;
    }
}
