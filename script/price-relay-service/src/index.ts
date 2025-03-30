import {
    createWalletClient, http, publicActions, getContract, 
    Address, TransactionReceipt, Hex, PublicClient, WalletClient
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import * as chains from 'viem/chains'; // Import all chains
import { 
    walletActionsL2, publicActionsL2, 
    createInteropSentL2ToL2Messages 
} from '@eth-optimism/viem';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// --- Configuration --- 
const privateKey = process.env.PRIVATE_KEY as Hex | undefined;
const rpcUrlA = process.env.RPC_URL_A;
const rpcUrlB = process.env.RPC_URL_B;
const senderAdapterAddressA = process.env.PRICE_SENDER_ADAPTER_ADDRESS_A as Address | undefined;
const receiverResolverAddressB = process.env.PRICE_RECEIVER_RESOLVER_ADDRESS_B as Address | undefined;
const chainNameA = process.env.CHAIN_NAME_A; // e.g., optimismSepolia
const chainNameB = process.env.CHAIN_NAME_B; // e.g., baseSepolia

// Basic validation
if (!privateKey || !rpcUrlA || !rpcUrlB || !senderAdapterAddressA || !receiverResolverAddressB || !chainNameA || !chainNameB) {
    throw new Error("Missing required environment variables (PRIVATE_KEY, RPC_URL_A, RPC_URL_B, PRICE_SENDER_ADAPTER_ADDRESS_A, PRICE_RECEIVER_RESOLVER_ADDRESS_B, CHAIN_NAME_A, CHAIN_NAME_B)");
}

// Dynamically get chain definitions from viem
const chainA = chains[chainNameA as keyof typeof chains];
const chainB = chains[chainNameB as keyof typeof chains];

if (!chainA || !chainB) {
    throw new Error(`Invalid chain name provided. Check CHAIN_NAME_A (${chainNameA}) and CHAIN_NAME_B (${chainNameB}). See viem/chains for options.`);
}

// --- ABIs (Minimal required for interaction) ---
// You might need to copy the full ABIs from your artifacts (out/...) for more complex interactions
const senderAdapterAbi = [
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "poolId",
                "type": "bytes32"
            },
            {
                "internalType": "int24",
                "name": "tick",
                "type": "int24"
            },
            {
                "internalType": "uint160",
                "name": "sqrtPriceX96",
                "type": "uint160"
            },
            {
                "internalType": "uint32",
                "name": "timestamp",
                "type": "uint32"
            }
        ],
        "name": "publishPriceData",
        "outputs": [
            {
                "internalType": "bool",
                "name": "success",
                "type": "bool"
            }
        ],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]; 

// --- Wallet Clients --- 
const account = privateKeyToAccount(privateKey);

const publicClientA = createWalletClient({
    chain: chainA,
    transport: http(rpcUrlA)
}).extend(publicActions).extend(publicActionsL2());

const walletClientA = createWalletClient({
    chain: chainA,
    transport: http(rpcUrlA),
    account
}).extend(publicActions).extend(publicActionsL2()).extend(walletActionsL2());

const walletClientB = createWalletClient({
    chain: chainB,
    transport: http(rpcUrlB),
    account
}).extend(publicActions).extend(publicActionsL2()).extend(walletActionsL2());

console.log(`Relay Service Configured:`);
console.log(`- Chain A (Sender): ${chainA.name} (${rpcUrlA})`);
console.log(`- Chain B (Receiver): ${chainB.name} (${rpcUrlB})`);
console.log(`- Sender Adapter (A): ${senderAdapterAddressA}`);
console.log(`- Receiver Resolver (B): ${receiverResolverAddressB}`);
console.log(`- Relayer Account: ${account.address}`);

// --- Main Relaying Logic --- 

// Example: Function to manually trigger a send and relay
// In a real service, you might listen for events or use a timer
async function sendAndRelayPrice(poolId: Hex, tick: number, sqrtPriceX96: bigint, timestamp: number) {
    console.log(`\nAttempting to send price data for pool ${poolId}...`);

    const senderContract = getContract({
        address: senderAdapterAddressA!,
        abi: senderAdapterAbi,
        client: walletClientA
    });

    try {
        // 1. Send the message from Chain A
        const sendTxHash = await senderContract.write.publishPriceData([
            poolId,
            tick,
            sqrtPriceX96,
            timestamp
        ]);
        console.log(`Send transaction initiated on Chain A: ${sendTxHash}`);
        const receiptA = await publicClientA.waitForTransactionReceipt({ hash: sendTxHash });
        console.log(`Send transaction confirmed on Chain A: ${receiptA.transactionHash} (Status: ${receiptA.status})`);

        if (receiptA.status !== 'success') {
            console.error('Send transaction failed on Chain A.');
            return;
        }

        // 2. Extract message details from receipt
        console.log('Extracting message details...');
        const sentMessages = await createInteropSentL2ToL2Messages(walletClientA, { receipt: receiptA });

        if (!sentMessages || sentMessages.sentMessages.length === 0) {
            console.error('No L2ToL2 message found in the transaction receipt.');
            return;
        }

        // Assuming only one message per transaction for simplicity
        const sentMessage = sentMessages.sentMessages[0]; 
        console.log(`Message details extracted: ID=${sentMessage.id}`);

        // 3. Relay the message on Chain B
        console.log('Relaying message on Chain B...');
        const relayTxHash = await walletClientB.interop.relayMessage({
            sentMessageId: sentMessage.id,
            sentMessagePayload: sentMessage.payload,
        });
        console.log(`Relay transaction initiated on Chain B: ${relayTxHash}`);
        const receiptRelay = await walletClientB.waitForTransactionReceipt({ hash: relayTxHash });
        console.log(`Relay transaction confirmed on Chain B: ${receiptRelay.transactionHash} (Status: ${receiptRelay.status})`);

        if (receiptRelay.status === 'success') {
            console.log('Message successfully relayed and executed on Chain B!');
        } else {
            console.error('Message relay transaction failed on Chain B.');
        }

    } catch (error) {
        console.error("Error during send/relay process:", error);
    }
}

// --- Example Usage --- 
// Replace with actual data and triggering logic
// This is just a placeholder to show how to call the function
async function runExample() {
    // Example data - replace with real data source
    const examplePoolId: Hex = '0x...'; // Replace with actual pool ID bytes32
    const exampleTick: number = 12345;
    const exampleSqrtPrice: bigint = BigInt('...'); // Replace with actual sqrtPriceX96
    const exampleTimestamp: number = Math.floor(Date.now() / 1000); 

    if (examplePoolId === '0x...') {
        console.warn("Placeholder data used. Replace with real data before running seriously.");
        return; 
    }

    await sendAndRelayPrice(examplePoolId, exampleTick, exampleSqrtPrice, exampleTimestamp);
}

// runExample(); // Uncomment to run the example when starting the script

console.log("\nRelay service setup complete. Waiting for triggers...");
// Add your actual triggering logic here (e.g., setInterval, event listener)
