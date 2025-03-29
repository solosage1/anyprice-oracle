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

const RESOLVER_ABI = [
    "function updateFromRemote((uint256 chainId, address origin, uint256 logIndex, uint256 blockNumber, uint256 timestamp) calldata _id, bytes calldata _data) external"
];

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
const crossL2Inbox = new ethers.Contract(CROSS_L2_INBOX_ADDRESS, CROSS_L2_INBOX_ABI, destProvider);

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

oracleAdapter.on("OraclePriceUpdate", async (source, sourceChainId, poolId, tick, sqrtPrice, timestamp, event) => {
    try {
        console.log(`\n[${new Date().toISOString()}] Oracle Update Detected:`);
        console.log(`  Chain ID: ${sourceChainId}`);
        console.log(`  Pool ID: ${poolId}`);
        console.log(`  Tick: ${tick}`);
        const priceValue = sqrtPrice.pow(2).div(ethers.BigNumber.from(2).pow(192));
        console.log(`  Price: ${ethers.utils.formatUnits(priceValue, 18)}`);
        console.log(`  Timestamp: ${new Date(timestamp * 1000).toISOString()}`);
        console.log(`  Block: ${event.blockNumber}, Log Index: ${event.logIndex}`);
        
        // Get the block to extract the timestamp
        const block = await sourceProvider.getBlock(event.blockNumber);
        
        // Construct the event identifier for CrossL2Inbox validation
        const identifier = {
            chainId: sourceChainId,
            origin: source,
            logIndex: event.logIndex,
            blockNumber: event.blockNumber,
            timestamp: block.timestamp
        };
        
        // Reconstruct the full event data (this is a simplified example)
        // In production, you would need the exact event data format
        // This includes the event signature (topic0) and all topics + data
        
        // This is the event signature hash
        const eventSig = ethers.utils.id("OraclePriceUpdate(address,uint256,bytes32,int24,uint160,uint32)");
        
        // Create topic bytes for indexed parameters
        const topic1 = ethers.utils.hexZeroPad(source, 32);
        const topic2 = ethers.utils.hexZeroPad(ethers.BigNumber.from(sourceChainId).toHexString(), 32);
        const topic3 = poolId;
        
        // Create the ABI encoded data section (all parameters for full decoding)
        const dataSection = ethers.utils.defaultAbiCoder.encode(
            ['address', 'uint256', 'bytes32', 'int24', 'uint160', 'uint32'],
            [source, sourceChainId, poolId, tick, sqrtPrice, timestamp]
        );
        
        // Combine into full event data
        const fullEventData = ethers.utils.hexConcat([
            eventSig,
            topic1,
            topic2,
            topic3,
            dataSection
        ]);
        
        console.log(`\nForwarding to destination chain...`);
        
        try {
            // Validate using CrossL2Inbox (this would normally be done by the blockchain infrastructure)
            // This validation is only for demonstration purposes
            const dataHash = ethers.utils.keccak256(fullEventData);
            const isValid = await crossL2Inbox.callStatic.validateMessage(identifier, dataHash);
            console.log(`CrossL2Inbox validation: ${isValid ? 'PASS' : 'FAIL'}`);
            
            if (!isValid) {
                console.log("Skipping update due to validation failure");
                return;
            }
        } catch (error) {
            console.log(`CrossL2Inbox validation error: ${error.message}`);
            // Continue anyway for demonstration purposes
        }
        
        // Call the resolver on the destination chain
        const tx = await resolver.updateFromRemote(identifier, fullEventData);
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