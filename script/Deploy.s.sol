// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RateToken} from "../src/RateToken.sol";
import {ResourceToken} from "../src/ResourceToken.sol";
import {ResourceTokenFactory} from "../src/ResourceTokenFactory.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationLedger} from "../src/ReputationLedger.sol";
import {AuditLog} from "../src/AuditLog.sol";
import {OrderBook} from "../src/OrderBook.sol";

/// @title Deploy — MANDATE testnet deployment script
/// @notice Deploys complete MANDATE ecosystem to MegaETH testnet (Chain ID 4326).
///         Saves deployment addresses to deployments/testnet-addresses.json.
contract Deploy is Script {
    // Test agent addresses for initial RATE distribution
    address constant TEST_AGENT_ALPHA = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // PHASE_3_PLACEHOLDER
    address constant TEST_AGENT_BETA = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // PHASE_3_PLACEHOLDER
    uint256 constant INITIAL_RATE_PER_AGENT = 1000 * 1e18; // PHASE_3_PLACEHOLDER

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("====================================");
        console2.log("MANDATE Testnet Deployment");
        console2.log("====================================");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("====================================\n");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy RATE token
        console2.log("1. Deploying RateToken...");
        RateToken rateToken = new RateToken(deployer);
        console2.log("   RATE:", address(rateToken));
        console2.log("   Initial supply:", rateToken.INITIAL_SUPPLY() / 1e18, "RATE\n");

        // 2. Deploy ResourceTokenFactory
        console2.log("2. Deploying ResourceTokenFactory...");
        ResourceTokenFactory factory = new ResourceTokenFactory(deployer);
        console2.log("   Factory:", address(factory));
        console2.log("");

        // 3. Deploy COMPUTE via factory
        console2.log("3. Deploying COMPUTE resource...");
        address computeToken = factory.deployResource("COMPUTE", "COMPUTE");
        console2.log("   COMPUTE:", computeToken);
        console2.log("");

        // 4. Deploy CHIPS via factory
        console2.log("4. Deploying CHIPS resource...");
        address chipsToken = factory.deployResource("CHIPS", "CHIPS");
        console2.log("   CHIPS:", chipsToken);
        console2.log("");

        // 5. Deploy AgentRegistry
        console2.log("5. Deploying AgentRegistry...");
        AgentRegistry registry = new AgentRegistry(deployer);
        console2.log("   AgentRegistry:", address(registry));
        console2.log("");

        // 6. Deploy ReputationLedger
        console2.log("6. Deploying ReputationLedger...");
        ReputationLedger repLedger = new ReputationLedger(deployer);
        console2.log("   ReputationLedger:", address(repLedger));
        console2.log("");

        // 7. Deploy AuditLog
        console2.log("7. Deploying AuditLog...");
        AuditLog audit = new AuditLog(deployer);
        console2.log("   AuditLog:", address(audit));
        console2.log("");

        // 8. Deploy OrderBook
        console2.log("8. Deploying OrderBook...");
        OrderBook orderBook =
            new OrderBook(address(rateToken), address(registry), address(repLedger), address(audit), deployer);
        console2.log("   OrderBook:", address(orderBook));
        console2.log("");

        // 9. Grant roles
        console2.log("9. Granting roles...");
        repLedger.grantRole(repLedger.RECORDER_ROLE(), address(orderBook));
        console2.log("   OK: OrderBook -> ReputationLedger.RECORDER_ROLE");

        audit.grantRole(audit.LOGGER_ROLE(), address(orderBook));
        console2.log("   OK: OrderBook -> AuditLog.LOGGER_ROLE");

        audit.grantRole(audit.LOGGER_ROLE(), address(registry));
        console2.log("   OK: AgentRegistry -> AuditLog.LOGGER_ROLE");
        console2.log("");

        // 10. Mint test RATE to agents
        console2.log("10. Minting test RATE to agents...");
        rateToken.transfer(TEST_AGENT_ALPHA, INITIAL_RATE_PER_AGENT);
        rateToken.transfer(TEST_AGENT_BETA, INITIAL_RATE_PER_AGENT);
        console2.log("   Agent Alpha:", TEST_AGENT_ALPHA);
        console2.log("   Amount:     ", INITIAL_RATE_PER_AGENT / 1e18, "RATE");
        console2.log("   Agent Beta: ", TEST_AGENT_BETA);
        console2.log("   Amount:     ", INITIAL_RATE_PER_AGENT / 1e18, "RATE");
        console2.log("");

        vm.stopBroadcast();

        // Print JSON for deployments/testnet-addresses.json
        console2.log("\n====================================");
        console2.log("Deployment Complete");
        console2.log("====================================");
        console2.log("\nCopy the following to deployments/testnet-addresses.json:\n");
        console2.log("{");
        console2.log('  "chainId":', block.chainid, ",");
        console2.log('  "deployer": "', vm.toString(deployer), '",');
        console2.log('  "timestamp":', block.timestamp, ",");
        console2.log('  "contracts": {');
        console2.log('    "RateToken": "', vm.toString(address(rateToken)), '",');
        console2.log('    "ResourceTokenFactory": "', vm.toString(address(factory)), '",');
        console2.log('    "COMPUTE": "', vm.toString(computeToken), '",');
        console2.log('    "CHIPS": "', vm.toString(chipsToken), '",');
        console2.log('    "AgentRegistry": "', vm.toString(address(registry)), '",');
        console2.log('    "ReputationLedger": "', vm.toString(address(repLedger)), '",');
        console2.log('    "AuditLog": "', vm.toString(address(audit)), '",');
        console2.log('    "OrderBook": "', vm.toString(address(orderBook)), '"');
        console2.log("  }");
        console2.log("}");
        console2.log("");
        console2.log("====================================");
        console2.log("\nDeployment Summary");
        console2.log("====================================");
        console2.log("RATE:             ", address(rateToken));
        console2.log("Factory:          ", address(factory));
        console2.log("COMPUTE:          ", computeToken);
        console2.log("CHIPS:            ", chipsToken);
        console2.log("AgentRegistry:    ", address(registry));
        console2.log("ReputationLedger: ", address(repLedger));
        console2.log("AuditLog:         ", address(audit));
        console2.log("OrderBook:        ", address(orderBook));
        console2.log("====================================");
    }
}
