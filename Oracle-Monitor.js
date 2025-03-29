// Cross-Chain Oracle Monitor
// Example script for monitoring and forwarding oracle events across chains

const { ethers } = require('ethers');
require('dotenv').config();

// Configuration
const SOURCE_RPC_URL = process.env.SOURCE_RPC_URL;
const DEST_RPC_URL = process.env.DEST_RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const ORACLE_ADAPTER_ADDRESS = process.env.ORACLE_ADAPTER_ADDRESS;
const RESOLVER_ADDRESS = process.env.RESOLVER_ADDRESS;

// ABI snippets (would be complete in production)
const ORACLE_ADAPTER_ABI = [
    "event OraclePriceUpdate(address indexed source, uint256 indexed sourceChainId, bytes32 indexed poolId, int24 tick, uint160 sqrtPriceX96, uint32 timestamp)"
];

const RESOLVER_ABI = [
    "function updateFromRemote((uint256 chainId, address origin, uint256 logIndex) calldata _id, bytes calldata _data) external"
];

// Create providers
const sourceProvider = new ethers.providers.JsonRpcProvider(SOURCE_RPC_URL);
const destProvider = new ethers.providers.JsonRpcProvider(DEST_RPC_URL);
const destSigner = new ethers.Wallet(PRIVATE_KEY, destProvider);

// Create contract instances
const oracleAdapter = new ethers.Contract(ORACLE_ADAPTER_ADDRESS, ORACLE_ADAPTER_ABI, sourceProvider);
const resolver = new ethers.Contract(RESOLVER_ADDRESS, RESOLVER_ABI, destSigner);

// Log setup info
console.log("Cross-Chain Oracle Monitor");
console.log("Source Chain:", SOURCE_RPC_URL);
console.log("Destination Chain:", DEST_RPC_URL);
console.log("Monitoring Oracle Adapter:", ORACLE_ADAPTER_ADDRESS);
console.log("Target Resolver:", RESOLVER_ADDRESS);
console.log("---");

// Setup event listener
console.log("Setting up event listener...");

oracleAdapter.on("OraclePriceUpdate", async (source, sourceChainId, poolId, tick, sqrtPrice, timestamp, event) => {
    try {
        console.log(`\n[${new Date().toISOString()}] Oracle Update Detected:`);
        console.log(`  Chain ID: ${sourceChainId}`);
        console.log(`  Pool ID: ${poolId}`);
        console.log(`  Tick: ${tick}`);
        console.log(`  Price: ${ethers.utils.formatUnits(sqrtPrice.pow(2).div(ethers.BigNumber.from(2).pow(192)), 18)}`);
        console.log(`  Timestamp: ${new Date(timestamp * 1000).toISOString()}`);
        console.log(`  Block: ${event.blockNumber}, Log Index: ${event.logIndex}`);
        
        // Construct the event identifier for CrossL2Inbox validation
        const identifier = {
            chainId: sourceChainId,
            origin: source,
            logIndex: event.logIndex
        };
        
        // Get the event data (complete event data with signature)
        // In production, you would need to get the full event data including the signature
        const eventData = event.data;
        const eventTopics = event.topics;
        
        console.log(`\nForwarding to destination chain...`);
        
        // Call the resolver on the destination chain
        const tx = await resolver.updateFromRemote(identifier, eventData);
        console.log(`Transaction sent: ${tx.hash}`);
        
        // Wait for transaction confirmation
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
        
        // Check for events from the resolver
        if (receipt.events && receipt.events.length > 0) {
            console.log(`Events emitted: ${receipt.events.length}`);
            for (const event of receipt.events) {
                if (event.event === 'PriceUpdated') {
                    console.log(`Price successfully updated on destination chain`);
                }
            }
        }
    } catch (error) {
        console.error(`Error processing event:`, error);
    }
});

// Also listen for past events (last 1000 blocks)
async function checkPastEvents() {
    const currentBlock = await sourceProvider.getBlockNumber();
    const fromBlock = Math.max(0, currentBlock - 1000);
    
    console.log(`Checking past events from block ${fromBlock} to ${currentBlock}...`);
    
    const filter = oracleAdapter.filters.OraclePriceUpdate();
    const events = await oracleAdapter.queryFilter(filter, fromBlock, currentBlock);
    
    console.log(`Found ${events.length} past events`);
    
    // Process past events if needed
    // This is useful when restarting the monitor to catch up on missed events
}

checkPastEvents();
console.log("Monitoring for new oracle updates...");