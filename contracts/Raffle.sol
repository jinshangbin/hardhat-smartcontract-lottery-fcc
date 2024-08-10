// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
 * @title 去中心化彩票抽奖系统
 * @author jack
 * @notice
 *
 * 1. 参与者进入到彩票系统，具体操作支付一些费用参与彩票抽奖
 * 2. 随机选出一个幸运者获取奖池全部奖金（抽取逻辑可验证的随机抽取，不能被篡改）
 * 3. 规定每隔一段时间选出一名幸运者（抽奖活动时间在部署时自定义）
 * 4. 整个过程是自动完成，部署之后无需任何操作
 *
 *
 * 需要用到技术有chainlink vrf -> 来从外部获取随机数
 * 另外一个自动执行 chainlink automation
 */

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

error Raffle_NotEnoughEthEntered();
error Raffle__TransferFailed();
error Raffle__RaffleNotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    uint256 private immutable i_enterLotteryFee; //参与抽奖费用

    address payable[] private s_players; //参与抽奖的参与者集合

    uint256 private immutable i_subscriptionId; //订阅ID

    bytes32 private immutable i_keyHash; //配置项 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B 部署时在配置文件中读取

    address private immutable i_vrfCoordinator; //配置项 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae 配置文件读取

    uint256 private immutable i_interval;

    uint256 public s_requestId; //请求随机数id

    uint256[] public s_randomWords; //随机数集合

    uint32 private s_callbackGasLimit; //请求汽油费用上线阈值

    uint16 constant REQUEST_CONFIRMATIONS = 3;

    uint32 constant NUM_WORDS = 1;

    address private s_luckyer; //幸运者

    RaffleState private s_raffleState; //抽奖活动状态

    uint256 private s_lastTimeStamp; //最后一次开奖时间

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //events
    event RaffleEnter(address indexed player);

    event ReturnedRandomness(uint256[] indexed randomWords);

    event luckyerPicked(address indexed luckyer);

    event RequestedRaffleLuckyer(uint256 indexed requsetId);

    constructor(
        uint256 enterLotteryFee,
        uint256 subscriptionId,
        bytes32 keyHash,
        address vrfCoordinator,
        uint32 callbackGasLimit,
        uint256 internal_time
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_enterLotteryFee = enterLotteryFee;
        i_subscriptionId = subscriptionId;
        i_keyHash = keyHash;
        i_interval = internal_time;
        i_vrfCoordinator = vrfCoordinator;
        s_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
    }

    //参与抽奖
    function enterLottery() public payable {
        if (msg.value < i_enterLotteryFee) {
            revert Raffle_NotEnoughEthEntered();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        bool isOpen = RaffleState.OPEN == s_raffleState; //判断活动状态是否为开奖状态
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval); //判断下次活动开始时间是否大于设置的时间间隔
        bool hasPlayers = s_players.length > 0; //判断参与抽奖人数是否大于0
        bool hasBalance = address(this).balance > 0; //判断奖池金额是否大于0
        upkeepNeeded = (isOpen && timePassed && hasBalance && hasPlayers); //所有条件都符合才可以开奖
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata) external override {
        (bool checkUpkeeped, ) = checkUpkeep("");
        if (!checkUpkeeped) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: s_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RequestedRaffleLuckyer(s_requestId);
    }

    //向chainlink VRF发起一个请求随机数的请求
    function requestRandomWords() external onlyOwner {
        // Will revert if subscription is not set and funded.
        s_requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: s_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    //完成获取随机数
    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal virtual override {
        //获取随机数之后根据随机数计算出幸运者
        //找到幸运者把奖池所有金额给到幸运者
        s_randomWords = randomWords;
        uint256 indexOfLuckyer = randomWords[0] % s_players.length; //计算出幸运者在参与者集合中的坐标
        address payable luckyer = s_players[indexOfLuckyer]; //根据坐标找到幸运者
        s_luckyer = luckyer;
        s_players = new address payable[](0); //清空参与者列表
        s_raffleState = RaffleState.OPEN; //设置抽奖状态为开奖状态
        s_lastTimeStamp = block.timestamp; //更新最后一次开奖时间

        (bool success, ) = luckyer.call{value: address(this).balance}("luckyer"); // 奖池金额全部划转到幸运者账户
        if (!success) {
            revert Raffle__TransferFailed();
        }

        emit luckyerPicked(luckyer);
    }

    function getEnterLotteryFee() public view returns (uint256) {
        return i_enterLotteryFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getLuckyer() public view returns (address) {
        return s_luckyer;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }
}
