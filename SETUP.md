# AnyPrice Setup Guide

This guide details the steps to set up, deploy, and interact with the AnyPrice contracts for cross-chain price fetching.

### Prerequisites

*   **Foundry:** Ensure Foundry is installed. Check with `forge --version`.
*   **Node.js & npm:** Ensure Node.js (v18 or later) and npm are installed. Check with `node --version` and `npm --version`.
*   **RPC Endpoints:** You need RPC URLs for two different OP Stack L2 test networks (e.g., OP Sepolia and Base Sepolia). Let's call them Chain A (source) and Chain B (destination).
*   **Private Key:** A wallet private key funded with test ETH on *both* Chain A and Chain B for deployment and transactions.
*   **Source Oracle (`TruncGeoOracleMulti`) Address:**
    *   **IMPORTANT:** AnyPrice requires a deployed `TruncGeoOracleMulti` contract (or a compatible Uniswap V4 style oracle) on Chain A to act as the price source.
    *   This project **does not** include a deployment script for `TruncGeoOracleMulti`.
    *   **For Hackathon Judges/Testers:** Since deploying a full Uniswap V4 pool and oracle is complex, you might need to:
        *   a) Deploy a simple mock oracle contract that returns fixed price data. You can adapt standard mock contracts for this.
        *   b) Find a publicly deployed instance of a suitable oracle on your chosen testnets (Chain A), if one exists.
    *   You will need the address of this deployed oracle for the `.env` setup.

### Environment Setup (Root Directory)

1.  **Copy `.env.example` to `.env`** in the project's root directory:
    ```bash
    cp .env.example .env
    ```
2.  **Fill `.env` variables**: Open the `.env` file and **replace all placeholder values** with your actual data.

    ```dotenv
    # Your deployer private key (REQUIRED, without 0x prefix)
    # Used for deploying contracts and potentially relaying messages.
    PRIVATE_KEY=YOUR_PRIVATE_KEY_HERE

    # RPC URL for Chain A (Source - where SenderAdapter & Oracle are) (REQUIRED)
    RPC_URL_A=YOUR_RPC_URL_FOR_CHAIN_A

    # RPC URL for Chain B (Destination - where ReceiverResolver is) (REQUIRED)
    RPC_URL_B=YOUR_RPC_URL_FOR_CHAIN_B

    # Chain ID number for Chain A (REQUIRED, e.g., Base Sepolia is 84532)
    CHAIN_ID_A=CHAIN_A_ID_NUMBER

    # Chain ID number for Chain B (REQUIRED, e.g., OP Sepolia is 11155420)
    CHAIN_ID_B=CHAIN_B_ID_NUMBER

    # Address of the PRE-DEPLOYED TruncGeoOracleMulti (or compatible) contract on Chain A (REQUIRED)
    # See Prerequisites section for details.
    TRUNC_ORACLE_MULTI_ADDRESS_A=ADDRESS_OF_ORACLE_ON_CHAIN_A

    # Optional: Etherscan API Keys for contract verification on public testnets
    # ETHERSCAN_API_KEY_A=YOUR_ETHERSCAN_KEY_CHAIN_A
    # ETHERSCAN_API_KEY_B=YOUR_ETHERSCAN_KEY_CHAIN_B
    ```

### Deployment

This Foundry script deploys `PriceReceiverResolver` to Chain B and `PriceSenderAdapter` to Chain A, linking them using the details from your `.env` file.

```bash
# Load environment variables from the root .env file
source .env

# Verify essential variables are set
if [ -z "$PRIVATE_KEY" ]; then echo "Error: PRIVATE_KEY is not set in .env"; exit 1; fi
if [ -z "$RPC_URL_A" ]; then echo "Error: RPC_URL_A is not set in .env"; exit 1; fi
if [ -z "$CHAIN_ID_A" ]; then echo "Error: CHAIN_ID_A is not set in .env"; exit 1; fi
if [ -z "$TRUNC_ORACLE_MULTI_ADDRESS_A" ]; then echo "Error: TRUNC_ORACLE_MULTI_ADDRESS_A is not set in .env"; exit 1; fi

# Optional but recommended: Build contracts first to catch compilation errors
forge build

# Run the deployment script
# It targets Chain A initially but handles deployment to Chain B internally.
# --broadcast sends the transactions. Remove it for a dry run.
forge script script/DeployL2L2.s.sol --broadcast --rpc-url $RPC_URL_A

# If deploying to public testnets and Etherscan keys are set in .env, add --verify:
# forge script script/DeployL2L2.s.sol --broadcast --rpc-url $RPC_URL_A --verify -vvvv
```

✨ **Deployment Output:** After the script finishes successfully, it will print the deployed contract addresses. Look for lines like:
`Deployed PriceSenderAdapter (Chain A) to: 0x...`
`Deployed PriceReceiverResolver (Chain B) to: 0x...`

**➡️ Copy these two addresses!** You will need them for the relay service setup and for interacting with the contracts later.

### Relaying Messages

Optimism L2-to-L2 messages require an off-chain relay process to finalize them on the destination chain. Choose one method:

1.  **Autorelay (Local Devnet Only):** If you are running a local OP Stack development network (like `op-stack-devnet` or `supersim`), you can often enable automatic relaying by starting the devnet with the `--interop.autorelay` flag (or similar). Check your devnet documentation. Messages will be relayed automatically without needing the manual service below.

2.  **Manual Relay Service (Testnets/Production):** For public testnets or production, you need a relay service. An example Node.js relay service is provided in `script/price-relay-service/`.

    *   **Navigate to the service directory:**
        ```bash
        cd script/price-relay-service
        ```
    *   **Install dependencies:**
        ```bash
        npm install
        ```
    *   **Create a local `.env` file for the service:** This service runs as a separate Node.js application and needs its *own* configuration, distinct from the root `.env`. Create a file named `.env` *inside the `script/price-relay-service` directory*.
    *   **Fill the service's `.env` file:**
        ```dotenv
        # Your deployer private key (REQUIRED) - Used to pay gas for relaying messages on Chain B.
        # Should be the same key as in the root .env file.
        PRIVATE_KEY=YOUR_PRIVATE_KEY_HERE

        # RPC URLs for both chains (REQUIRED) - Copied from the root .env file.
        RPC_URL_A=YOUR_RPC_URL_FOR_CHAIN_A
        RPC_URL_B=YOUR_RPC_URL_FOR_CHAIN_B

        # Deployed contract addresses (REQUIRED) - From the deployment script output.
        PRICE_SENDER_ADAPTER_ADDRESS_A=DEPLOYED_SENDER_ADDRESS_ON_CHAIN_A
        PRICE_RECEIVER_RESOLVER_ADDRESS_B=DEPLOYED_RECEIVER_ADDRESS_ON_CHAIN_B

        # viem chain names (REQUIRED) - Used by the viem library to configure chain interactions.
        # Find the correct names in the `viem` documentation (search viem/chains) or online.
        # Examples: baseSepolia, optimismSepolia, sepolia, mainnet, optimism, base
        CHAIN_NAME_A=baseSepolia # Example: Replace with Chain A's viem name
        CHAIN_NAME_B=optimismSepolia # Example: Replace with Chain B's viem name
        ```
    *   **Start the relay service:**
        ```bash
        # Make sure you are still in the script/price-relay-service directory
        npm start
        ```
    *   **(Note:** The provided `index.ts` is a *basic example polling service*. It periodically triggers a price update on Chain A and then attempts to relay any pending messages to Chain B. For production, you'd likely want a more robust event-driven or trigger-based relay mechanism.)*

### Triggering a Price Update Manually (Example using `cast`)

If you are *not* using the example relay service's automatic trigger (e.g., you are only running the relay part, or using autorelay), you can manually trigger the `PriceSenderAdapter` on Chain A to fetch a price and send the cross-chain message.

```bash
# --- Set these variables in your terminal ---

# Pool ID: The unique identifier (bytes32) for the asset pool in your TruncGeoOracleMulti.
# You must know this from your oracle setup. For mocks, you might use a simple value.
POOL_ID=0xYOUR_POOL_ID_BYTES32

# Sender Address: The address of PriceSenderAdapter deployed on Chain A (from deployment output).
SENDER_ADAPTER_ADDR=DEPLOYED_SENDER_ADDRESS_ON_CHAIN_A

# Owner PK: Your private key (from root .env).
OWNER_PK=$PRIVATE_KEY

# RPC A: RPC URL for Chain A (from root .env).
RPC_A=$RPC_URL_A

# Example Price Data: Replace with actual data if possible, or use these placeholders.
# In a real scenario, this data would typically be read from the TruncGeoOracleMulti first.
TICK=12345
SQRT_PRICE=5678901234567890123456789012 # Example uint160 value
TIMESTAMP=$(date +%s) # Current Unix timestamp

# --- Send the transaction ---
# This calls the publishPriceData function on the PriceSenderAdapter contract.
cast send --private-key $OWNER_PK --rpc-url $RPC_A \
  $SENDER_ADAPTER_ADDR "publishPriceData(bytes32,int24,uint160,uint32)" \
  $POOL_ID $TICK $SQRT_PRICE $TIMESTAMP
```
This transaction initiates the cross-chain message sending process from Chain A. If a relay mechanism (auto or manual service) is active, the message should eventually be processed on Chain B.

### Reading the Price on Chain B (Example using `cast`)

Once a message has been successfully relayed and processed, your dApp or you (using `cast`) can read the stored price data from the `PriceReceiverResolver` contract on Chain B.

```bash
# --- Set these variables in your terminal ---

# Resolver Address: The address of PriceReceiverResolver deployed on Chain B (from deployment output).
RESOLVER_ADDR=DEPLOYED_RECEIVER_ADDRESS_ON_CHAIN_B

# RPC B: RPC URL for Chain B (from root .env).
RPC_B=$RPC_URL_B

# Source Chain ID: The Chain ID of Chain A (the source chain), as specified in your root .env.
SOURCE_CHAIN_ID_A=$CHAIN_ID_A # e.g., 84532 for Base Sepolia

# Pool ID: The *same* bytes32 Pool ID used when triggering the price update.
POOL_ID=0xYOUR_POOL_ID_BYTES32

# --- Call getPrice function ---
# Function signature: getPrice(uint256 sourceChainId, bytes32 poolId)
# Returns a struct: (int24 tick, uint160 sqrtPriceX96, uint32 timestamp, bool isValid)
cast call --rpc-url $RPC_B $RESOLVER_ADDR \
  "getPrice(uint256,bytes32)(int24,uint160,uint32,bool)" \
  $SOURCE_CHAIN_ID_A $POOL_ID
```

**➡️ Interpreting the Output:** The command will return the price data fields: `(tick, sqrtPriceX96, timestamp, isValid)`.

**🚨 Crucially, always check the `isValid` flag (the last boolean value).**
*   If `true`, a valid price has been received and stored for that `sourceChainId` and `poolId`, and the other values represent the latest relayed price.
*   If `false`, no valid price has been stored yet (or the last update failed validation). Do not use the potentially stale/zero `tick`, `sqrtPriceX96`, or `timestamp` values.

This completes the setup and interaction guide. Good luck! 