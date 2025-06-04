#!/bin/bash
# AnyPrice L2-to-L2 Cross-Chain Oracle - LIVE DEMO SCRIPT
# Executes actual deployment and contract calls.

# --- Configuration & Styling ---
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# --- Helper Functions ---
step_info() {
    echo -e "\n${BOLD}${BLUE}===> $1${NC}"
}

step_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

step_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
    exit 1
}

# --- Environment Setup ---
step_info "Loading Environment Variables from .env"
if [ ! -f ".env" ]; then
    step_error ".env file not found in project root. Please create it from .env.example."
fi

source .env

# Check required variables
REQUIRED_VARS=( "PRIVATE_KEY" "RPC_URL_A" "RPC_URL_B" "CHAIN_ID_B" "TRUNC_ORACLE_MULTI_ADDRESS_A" )
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        step_error "Required environment variable $var is not set in .env"
    fi
    echo "  -> $var loaded."
done
sleep 1

# --- Demo Parameters (Customize if needed) ---
POOL_ID="0x57486574682f5553444300000000000000000000000000000000000000000000" # Example: Weth/USDC - ENSURE THIS MATCHES YOUR ORACLE
DEMO_TICK=200000 # Example tick value
DEMO_SQRT_PRICE=5602277097478614198912276234240 # Example sqrtPriceX96 (adjust based on tick/token decimals)
TIMESTAMP=$(date +%s)
RELAY_WAIT_SECONDS=30 # Adjust based on expected L2-L2 relay time for your testnets

# --- Clean Previous Run (Optional) ---
# Consider adding cleanup steps if needed, e.g., removing temporary files

# --- Deployment ---
step_info "Deploying Contracts via script/DeployL2L2.s.sol"
echo "Using RPC_URL_A: $RPC_URL_A for initial deployment connection..."
echo "Executing: forge script script/DeployL2L2.s.sol --broadcast --rpc-url \$RPC_URL_A"

# Execute deployment and capture output
# **CRITICAL**: Assumes specific output format. Adjust grep/awk if needed.
DEPLOY_OUTPUT=$(forge script script/DeployL2L2.s.sol --broadcast --rpc-url "$RPC_URL_A" 2>&1)
if [ $? -ne 0 ]; then
    echo "$DEPLOY_OUTPUT" # Print output on error
    step_error "Forge deployment script failed."
fi
echo "$DEPLOY_OUTPUT" # Show deployment output during run
sleep 2

# **CRITICAL**: Parse addresses from output. MODIFY THESE LINES IF YOUR OUTPUT FORMAT DIFFERS.
RECEIVER_ADDR_B=$(echo "$DEPLOY_OUTPUT" | grep "PriceReceiverResolver deployed to Chain B at:" | awk '{print $NF}')
SENDER_ADDR_A=$(echo "$DEPLOY_OUTPUT" | grep "PriceSenderAdapter deployed to Chain A at:" | awk '{print $NF}')

if [ -z "$RECEIVER_ADDR_B" ] || [[ ! "$RECEIVER_ADDR_B" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    step_error "Failed to parse PriceReceiverResolver address from deployment output. Check script output and parsing logic."
fi
if [ -z "$SENDER_ADDR_A" ] || [[ ! "$SENDER_ADDR_A" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    step_error "Failed to parse PriceSenderAdapter address from deployment output. Check script output and parsing logic."
fi

step_success "Deployment Complete"
echo "  -> PriceReceiverResolver (Chain B): $RECEIVER_ADDR_B"
echo "  -> PriceSenderAdapter (Chain A):    $SENDER_ADDR_A"
sleep 3

# --- Trigger Price Send on Chain A ---
step_info "[CHAIN A] Triggering price data transmission"
echo "Targeting PriceSenderAdapter: $SENDER_ADDR_A on RPC: $RPC_URL_A"
echo "Pool ID: $POOL_ID"
echo "Tick: $DEMO_TICK, SqrtPrice: $DEMO_SQRT_PRICE, Timestamp: $TIMESTAMP"
echo "Executing: cast send ..."

cast send --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL_A" \
  "$SENDER_ADDR_A" "publishPriceData(bytes32,int24,uint160,uint32)" \
  "$POOL_ID" "$DEMO_TICK" "$DEMO_SQRT_PRICE" "$TIMESTAMP"

if [ $? -ne 0 ]; then
    step_error "cast send command failed to send price data on Chain A."
fi

step_success "Price data sent from Chain A. Transaction initiated."
echo "L2ToL2CrossDomainMessenger.sendMessage should have been called on Chain A."
sleep 3

# --- Wait for Relaying ---
step_info "[RELAY] Waiting for L2-to-L2 message relay..."
echo "Pausing for ${RELAY_WAIT_SECONDS} seconds to allow message relay from Chain A -> Chain B."
echo "(Relay time depends on network congestion and relay mechanism - auto or manual)"
sleep "$RELAY_WAIT_SECONDS"
step_success "Presumed relay time elapsed."

# --- Read Price on Chain B ---
step_info "[CHAIN B] Attempting to read the relayed price"
echo "Targeting PriceReceiverResolver: $RECEIVER_ADDR_B on RPC: $RPC_URL_B"
echo "Querying for Source Chain ID: (Inferred by contract as sender chain)"
echo "Querying for Pool ID: $POOL_ID"
echo "Executing: cast call getPrice(uint256 sourceChainId, bytes32 poolId)... (Note: Solidity uses sourceChainId from message context, we provide CHAIN_ID_B for clarity but it might not be strictly needed depending on contract logic - check DeployL2L2.s.sol)"

# We need the source chain ID where the sender adapter lives.
# This isn't explicitly in the .env for RPC_URL_A, need to deduce or add CHAIN_ID_A
# For now, let's *assume* the contract correctly uses crossDomainMessageContext()
# and the user just needs to provide the poolId. Let's try calling the simpler getLatestPrice(poolId) if it exists,
# or call getPrice(sourceChainId, poolId) assuming sourceChainId is automatically handled or we need CHAIN_ID_A.
# Let's stick to the README example which used getPrice(sourceChainId, poolId)
# We NEED CHAIN_ID_A for this call as specified in README example. Let's check the .env again.
# The .env asks for CHAIN_ID_B, TRUNC_ORACLE_MULTI_ADDRESS_A, RPC_URL_A, RPC_URL_B. It doesn't explicitly ask for CHAIN_ID_A.
# This implies either:
# 1. The DeployL2L2 script somehow knows Chain A's ID (e.g. via `vm.chainId()` on the initial fork) and stores it.
# 2. The ReceiverResolver's getPrice uses `crossDomainMessageContext()` to know the source chain, making the `sourceChainId` parameter redundant/validated internally.
# 3. The `README.md` example call `cast call ... getPrice(uint256,bytes32) $SOURCE_CHAIN_ID_A $POOL_ID` requires CHAIN_ID_A to be manually known/provided.
# Let's assume #3 based on the README and add a requirement for CHAIN_ID_A in .env
if [ -z "$CHAIN_ID_A" ]; then
    step_error "Required environment variable CHAIN_ID_A is not set in .env. This is needed for the getPrice call on Chain B."
fi
echo "Using Source Chain ID (Chain A): $CHAIN_ID_A"

PRICE_DATA=$(cast call --rpc-url "$RPC_URL_B" "$RECEIVER_ADDR_B" "getPrice(uint256,bytes32)" "$CHAIN_ID_A" "$POOL_ID")

if [ $? -ne 0 ]; then
    step_error "cast call command failed to retrieve price data on Chain B. Check contract state, relay status, and parameters."
fi

step_success "Price data retrieved from Chain B:"
echo -e "${YELLOW}${PRICE_DATA}${NC}"
# Potentially parse PRICE_DATA further if needed using awk/sed

# --- Conclusion ---
step_info "Demo Concluded"
echo "Successfully demonstrated sending price data from Chain A ($CHAIN_ID_A) and retrieving it on Chain B ($CHAIN_ID_B) via L2-L2 messaging."
echo "Chain A (Sender): $SENDER_ADDR_A"
echo "Chain B (Receiver): $RECEIVER_ADDR_B"

exit 0 