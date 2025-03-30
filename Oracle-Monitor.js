// Cross-Chain Oracle Monitor
// Example script for monitoring and forwarding oracle events across chains using the CrossL2Inbox pattern

const { ethers } = require('ethers');
require('dotenv').config();

// Configuration
const SOURCE_RPC_URL = process.env.SOURCE_RPC_URL;
const DEST_RPC_URL = process.env.DEST_RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const ORACLE_ADAPTER_ADDRESS = process.env.ORACLE_ADAPTER_ADDRESS;
const RESOLVER_ADDRESS = process.env.RESOLVER_ADDRESS;
const CROSS_L2_INBOX_ADDRESS = process.env.CROSS_L2_INBOX_ADDRESS || "0x4200000000000000000000000000000000000022"; // Default Optimism CrossL2Inbox address

// ABI snippets (would be complete in production)
const ORACLE_ADAPTER_ABI = [
    "event OraclePriceUpdate(address indexed source, uint256 indexed sourceChainId, bytes32 indexed poolId, int24 tick, uint160 sqrtPriceX96, uint32 timestamp)"
];

// Updated ABI to match the new updateFromRemote signature
const RESOLVER_ABI = [
    "function updateFromRemote((uint256 chainId, address origin, uint256 logIndex, uint256 blockNumber, uint256 timestamp) calldata _id, bytes32[] calldata topics, bytes calldata data) external"
];

// Keep this ABI if doing the illustrative pre-check
const CROSS_L2_INBOX_ABI = [
    "function validateMessage((uint256 chainId, address origin, uint256 logIndex, uint256 blockNumber, uint256 timestamp) calldata _id, bytes32 _dataHash) external view returns (bool)"
];

// Create providers
const sourceProvider = new ethers.providers.JsonRpcProvider(SOURCE_RPC_URL);
const destProvider = new ethers.providers.JsonRpcProvider(DEST_RPC_URL);
const destSigner = new ethers.Wallet(PRIVATE_KEY, destProvider);

// Create contract instances
const oracleAdapter = new ethers.Contract(ORACLE_ADAPTER_ADDRESS, ORACLE_ADAPTER_ABI, sourceProvider);
const resolver = new ethers.Contract(RESOLVER_ADDRESS, RESOLVER_ABI, destSigner);
// Only instantiate if doing the pre-check
// const crossL2Inbox = new ethers.Contract(CROSS_L2_INBOX_ADDRESS, CROSS_L2_INBOX_ABI, destProvider);

// Log setup info
console.log("Cross-Chain Oracle Monitor (CrossL2Inbox Pattern)");
console.log("Source Chain:", SOURCE_RPC_URL);
console.log("Destination Chain:", DEST_RPC_URL);
console.log("Monitoring Oracle Adapter:", ORACLE_ADAPTER_ADDRESS);
console.log("Target Resolver:", RESOLVER_ADDRESS);
console.log("CrossL2Inbox Address:", CROSS_L2_INBOX_ADDRESS);
console.log("---");

// Setup event listener
console.log("Setting up event listener...");

// The ethers event object conveniently provides `event.args`, `event.topics`, and `event.data`
oracleAdapter.on("OraclePriceUpdate", async (source, sourceChainId, poolId, tick, sqrtPrice, timestamp, event) => {
    try {
        console.log(`\n[${new Date().toISOString()}] Oracle Update Detected:`);
        console.log(`  Chain ID: ${sourceChainId}`);
        console.log(`  Pool ID: ${poolId}`);
        console.log(`  Tick: ${tick}`);
        // Calculate approximate price for logging (optional)
        try {
            const priceValue = sqrtPrice.pow(2).div(ethers.BigNumber.from(2).pow(192));
            console.log(`  Approx Price: ${ethers.utils.formatUnits(priceValue, 18)}`);
        } catch (e) {
            console.log(`  Could not calculate approx price: ${e.message}`);
        }
        console.log(`  Timestamp: ${new Date(timestamp * 1000).toISOString()}`);
        console.log(`  Block: ${event.blockNumber}, Log Index: ${event.logIndex}, Tx Hash: ${event.transactionHash}`);

        // Get the source block to extract the correct block timestamp for the Identifier
        const block = await sourceProvider.getBlock(event.blockNumber);
        if (!block) {
            console.error(`Failed to fetch block ${event.blockNumber} from source chain.`);
            return; // Skip processing if block info unavailable
        }

        // Construct the event identifier for CrossL2Inbox validation and replay protection
        const identifier = {
            chainId: sourceChainId.toString(), // Ensure it's a string or BigNumber compatible type if needed
            origin: source, // address from event args is correct origin
            logIndex: event.logIndex,
            blockNumber: event.blockNumber,
            timestamp: block.timestamp // Use the actual block timestamp
        };

        // Get the raw topics and data from the event object
        const topics = event.topics; // Array of bytes32 topics (includes signature hash at index 0)
        const data = event.data;     // Raw bytes data (ABI encoded non-indexed params)

        console.log(`\nForwarding to destination chain...`);
        console.log(`  Identifier:`, identifier);
        console.log(`  Topics Count: ${topics.length}`);
        console.log(`  Data Length: ${ethers.utils.hexDataLength(data)} bytes`);

        /*
        // Optional Pre-check (Illustrative - real validation is implicit on-chain)
        // Note: This requires hashing the concatenated topics and data in the specific way the L1->L2 bridge expects,
        // which might be complex/different from just hashing `data`. Omitted for clarity as it's not essential for function.
        try {
            const crossL2Inbox = new ethers.Contract(CROSS_L2_INBOX_ADDRESS, CROSS_L2_INBOX_ABI, destProvider);
            // const dataHash = ethers.utils.keccak256(data); // This might be too simplistic for CrossL2Inbox proof format
            // const isValid = await crossL2Inbox.callStatic.validateMessage(identifier, dataHash);
            // console.log(`Illustrative Pre-check validation: ${isValid ? 'PASS' : 'FAIL'}`);
            // if (!isValid) {
            //     console.log("Skipping update due to pre-check validation failure");
            //     return;
            // }
            console.log("(Skipping illustrative pre-check)");
        } catch (error) {
            console.log(`Illustrative Pre-check error: ${error.message}`);
            // Continue anyway
        }
        */

        // Call the resolver on the destination chain with standard topics and data
        const tx = await resolver.updateFromRemote(identifier, topics, data);
        console.log(`Transaction sent: ${tx.hash}`);

        // Wait for transaction confirmation
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);

        // Check for events from the resolver (optional)
        if (receipt.events && receipt.events.length > 0) {
            console.log(`Resolver events emitted: ${receipt.events.length}`);
            receipt.events.forEach(ev => {
                if (ev.event === 'PriceUpdated') {
                    console.log(`  -> Price successfully updated on destination chain for pool ${ev.args.poolId}`);
                }
            });
        }

    } catch (error) {
        console.error(`\n[${new Date().toISOString()}] Error processing event:`, error);
        // Implement more robust error handling/retry logic here for production
    }
});

// Function to check past events (optional, useful on startup)
async function checkPastEvents() {
    try {
        const currentBlock = await sourceProvider.getBlockNumber();
        const fromBlock = Math.max(0, currentBlock - 1000); // Check last 1000 blocks

        console.log(`Checking past events from block ${fromBlock} to ${currentBlock}...`);

        const filter = oracleAdapter.filters.OraclePriceUpdate();
        const pastEvents = await oracleAdapter.queryFilter(filter, fromBlock, currentBlock);

        console.log(`Found ${pastEvents.length} past events.`);

        // Basic sequential processing (can be parallelized with care)
        for (const event of pastEvents) {
            // Avoid reprocessing if already handled by the live listener
            // A simple check (not foolproof): check if already processed in contract? Requires reading state.
            // Or maintain local cache/db of processed event IDs (transactionHash + logIndex)
            console.log(`Processing past event from block ${event.blockNumber}...`);
            // Call the same handler logic (could refactor into a separate function)
            // await processOracleUpdateEvent(event); // Assuming handler logic is refactored
        }
        console.log("Finished checking past events.");

    } catch(error) {
        console.error("Error checking past events:", error);
    }
}

// checkPastEvents(); // Uncomment to run past event check on startup
console.log("Monitoring for new oracle updates...");