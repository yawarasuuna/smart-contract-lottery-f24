// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console2} from "forge-std/Script.sol";

/**
 * @title A sample Raffle contract
 * @author yawarasuuna
 * @notice Don't get addicted. This contract is for creating a si mple raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__entranceFeeWasNotMet(); // more gas efficient than require+revertStrings;
    error Raffle__notEnoughTimeHasPassed();
    error Raffle__winnerDidNotGetFunds();
    error Raffle__isNotOpen();
    error Raffle__upkeepNotNeeded(
        uint256 balance,
        uint256 playersLenght,
        uint256 raffleState
    );

    /* Type Declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /* State Variables */
    address public rafflers;
    bytes32 private i_keyHash;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint32 private immutable i_callbackGasLimit;

    // @dev Duration of interval in seconds;
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_subscriptionId;
    uint256 private s_lastTimeStamp;

    address private s_recentWinner;
    address payable[] private s_players;

    mapping(address => uint256) rafflersToAmountOfTickets;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEnter(address indexed player);
    event RaffleWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; // same as RaffleState(0), but former is more readeable; // defaults contract to enum OPEN
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Send MOORe"); // solidity < 0.8.4; readibility good, gas efficiency bad due to storing string than using error();
        if (msg.value < i_entranceFee) {
            revert Raffle__entranceFeeWasNotMet();
        } // solidity ^0.8.4; readibility bad;
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__isNotOpen();
        } // require(s_raffleState == RaffleState.OPEN,"Calculating winner, please try again in 1 min");

        // require(msg.value >= i_entranceFee, Raffle__entranceFeeWasNotMet()); // solidity ^0.8.26; readibility good, less gas efficient than if+error(); only compile via IR;
        s_players.push(payable(msg.sender)); // emits events whenever updating storage variable;
        // evm logging functionality;
        // inside logs are events, which allows to print stuff to this logging structure, which is more efficient than, eg, saving it to storage variable;
        // events and logs are in this special data structure, which isnt accessible to smart contracts, which is why its cheaper ;
        // tied to smart contract or account address emitted it in these txs
        // list for the events; off chain transactions usually are listening to these events; incredible important to front ends, chainlink, graph
        /* looks similar to calling function */
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is the function that Chainlink nodes will call to see if the lottery is ready
     * to have a winner picked. For upkeepNeeded to be true:
     * 1. Time interval has passed betweenm raffle runs
     * 2. Lotter is open
     * 3. Contract has ETH
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasETH = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasETH && hasPlayers;
        return (upkeepNeeded, "");
    }

    // MANUAL PROCESS, before chainlink automation:
    // function pickWinner() external payable {
    //     block.timestamp - s_lastTimeStamp > i_interval;
    //     if ((block.timestamp - s_lastTimeStamp) < i_interval) {
    //         revert Raffle__notEnoughTimeHasPassed();
    //     }
    //     s_raffleState = RaffleState.CALCULATING; // once someone engage VRFRequest, raffle is calculating and no one can enter the raffle
    //     VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
    //         .RandomWordsRequest({
    //             keyHash: i_keyHash,
    //             subId: i_subscriptionId,
    //             requestConfirmations: REQUEST_CONFIRMATIONS,
    //             callbackGasLimit: i_callbackGasLimit,
    //             numWords: NUM_WORDS,
    //             extraArgs: VRFV2PlusClient._argsToBytes(
    //                 // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
    //                 VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
    //             )
    //         });
    //     uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    // }

    function performUpkeep(bytes calldata /* performData */) external payable {
        block.timestamp - s_lastTimeStamp > i_interval;
        (bool upkeepNeeded, ) = checkUpkeep(""); // whenever a type of variable is used inside a function, it cant be calldata, anything generated by smart contract isnt calldata, call data can only be generated from user transaction input, so we have to update function checkUpkeep bytes to memory;
        if (!upkeepNeeded) {
            revert Raffle__upkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING; // once someone engage VRFRequest, raffle is calculating and no one can enter the raffle
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        // s_vrfCoordinator.requestRandomWords(request); v1
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); // v2
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length; // randomWords is an array of size 1, as defined by NUM_WORDS, so we use 0
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN; // After winner is picked, raffle reopens
        s_players = new address payable[](0); // resets array, otherwise, previous players would play on the next raffle again
        s_lastTimeStamp = block.timestamp; // interval/clock restarts as well to current timestamp
        emit RaffleWinner(s_recentWinner);

        (bool success, ) = payable(recentWinner).call{
            value: address(this).balance
        }("");

        if (!success) {
            revert Raffle__winnerDidNotGetFunds();
        }
    }

    /**
     * Getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
