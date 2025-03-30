### Prerequisites

*   Foundry installed (`forge --version`)
*   Node.js (v18+) & npm installed (`node --version`, `npm --version`)
*   RPC endpoints for two OP Stack L2 chains (e.g., OP Sepolia and Base Sepolia).
*   A deployer private key funded with test ETH on both chains.
*   **IMPORTANT:** The `TruncGeoOracleMulti` contract **must be deployed beforehand** on the source chain (Chain A). This project **does not** currently include a deployment script for `TruncGeoOracleMulti` itself. You will need its deployed address.

### Environment Setup

1.  **Copy `.env.example` to `.env`**:
    ```bash
    cp .env.example .env
    ```
2.  **Fill `.env` variables**:
    ```dotenv
    # Your deployer private key (without 0x prefix)
    PRIVATE_KEY=YOUR_PRIVATE_KEY_HERE

    # RPC URL for Chain A (Source - where SenderAdapter & Oracle are)
    RPC_URL_A=YOUR_RPC_URL_FOR_CHAIN_A

    # RPC URL for Chain B (Destination - where ReceiverResolver is)
    RPC_URL_B=YOUR_RPC_URL_FOR_CHAIN_B

    # Chain ID number for Chain A (e.g., Base Sepolia is 84532)
    CHAIN_ID_A=CHAIN_A_ID_NUMBER

    # Chain ID number for Chain B (e.g., OP Sepolia is 11155420)
    CHAIN_ID_B=CHAIN_B_ID_NUMBER

    # Address of the PRE-DEPLOYED TruncGeoOracleMulti contract on Chain A
    TRUNC_ORACLE_MULTI_ADDRESS_A=ADDRESS_OF_ORACLE_ON_CHAIN_A

    # Optional: Etherscan API Keys for verification
    # ETHERSCAN_API_KEY_A=YOUR_ETHERSCAN_KEY_CHAIN_A
    # ETHERSCAN_API_KEY_B=YOUR_ETHERSCAN_KEY_CHAIN_B
    ```

### Deployment

This script deploys `PriceReceiverResolver` (Chain B) and `PriceSenderAdapter` (Chain A).

```bash
# Load environment variables
source .env

# Check CHAIN_ID_A is set
if [ -z "$CHAIN_ID_A" ]; then echo "Error: CHAIN_ID_A not set"; exit 1; fi

# Run deployment
forge script script/DeployL2L2.s.sol --broadcast --rpc-url $RPC_URL_A

# Optionally add --verify for public testnets
```
**Note the deployed contract addresses printed by the script.**

### Relaying Messages

Optimism L2-to-L2 messages need relaying. Use either:

1.  **Autorelay (Local Devnet):** Run your devnet (e.g., `supersim`) with the `--interop.autorelay` flag.
2.  **Manual Relay Service:**
    *   `cd script/price-relay-service`
    *   `npm install`
    *   Create `script/price-relay-service/.env` with `PRIVATE_KEY`, `RPC_URL_A`, `RPC_URL_B`, `PRICE_SENDER_ADAPTER_ADDRESS_A`, `PRICE_RECEIVER_RESOLVER_ADDRESS_B`, `CHAIN_NAME_A`, `CHAIN_NAME_B` (use viem chain names like `optimismSepolia`).
    *   `npm start`
    *   *(Note: This is a basic example polling service)*

### Triggering a Price Update Manually (Example)

Use `cast` if not using the relay service's trigger:

```bash
# --- Set these variables ---
POOL_ID=0xYOUR_POOL_ID_BYTES32 # From TruncGeoOracleMulti setup
SENDER_ADAPTER_ADDR=DEPLOYED_SENDER_ADDRESS_ON_CHAIN_A
OWNER_PK=$PRIVATE_KEY
RPC_A=$RPC_URL_A
# Example data (replace with actual)
TICK=12345
SQRT_PRICE=5678901234567890123456789012
TIMESTAMP=$(date +%s)

# --- Send the transaction ---
cast send --private-key $OWNER_PK --rpc-url $RPC_A \
  $SENDER_ADAPTER_ADDR "publishPriceData(bytes32,int24,uint160,uint32)" \
  $POOL_ID $TICK $SQRT_PRICE $TIMESTAMP
```

### Reading the Price on Chain B

Use `cast` to query the `PriceReceiverResolver`:

```bash
# --- Set these variables ---
RESOLVER_ADDR=DEPLOYED_RECEIVER_ADDRESS_ON_CHAIN_B
RPC_B=$RPC_URL_B
SOURCE_CHAIN_ID_A=CHAIN_A_ID_NUMBER # e.g., 84532
POOL_ID=0xYOUR_POOL_ID_BYTES32

# --- Call getPrice ---
# Returns (int24 tick, uint160 sqrtPriceX96, uint32 timestamp, bool isValid)
cast call --rpc-url $RPC_B $RESOLVER_ADDR \
  "getPrice(uint256,bytes32)(int24,uint160,uint32,bool)" \
  $SOURCE_CHAIN_ID_A $POOL_ID
```
**Check the `isValid` flag (last boolean value) before using the data.** 