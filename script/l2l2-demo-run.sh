#!/bin/bash
# AnyPrice L2-to-L2 Cross-Chain Oracle Demo Script
# This script provides timed visual cues to match your narration

# Text styling
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

clear

# [0:00 - 0:08] — Title + Hook
echo -e "${BOLD}${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   AnyPrice — L2-to-L2 Cross-Chain Oracle Access Demo (Optimism)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"
echo -e "🚀 Initializing AnyPrice L2-to-L2 Demo..."
sleep 5

# [0:08 - 0:20] — Problem
echo -e "\n${BOLD}${YELLOW}[SCENARIO: Chain B Needs Price from Chain A]${NC}"
echo -e "⛓️  Your dApp is on ${BOLD}Chain B${NC} (e.g., Optimism)"
sleep 4
echo -e "📉 It needs the price of WETH/USDC, but the deepest liquidity is on ${BOLD}Chain A${NC} (e.g., Unichain)"
sleep 4
echo -e "${RED}❌ PROBLEM: Standard oracles on Chain B don't have this fresh price.${NC}"
echo -e "${YELLOW}✗ Old L2Inbox methods required complex off-chain relayers & proof systems.${NC}"
sleep 4

# [0:20 - 0:35] — Solution
echo -e "\n${BOLD}${BLUE}[ANYPRICE L2-L2 SOLUTION]${NC}"
echo -e "🛠️  Use ${BOLD}PriceReceiverResolver${NC} on Chain B:"
echo -e "${CYAN}"
echo "  // 1. PriceSenderAdapter on Chain A sends message via L2-L2 Messenger"
echo "  // 2. Message relayed (auto or manual) to Chain B"
echo "  // 3. PriceReceiverResolver receives, validates, stores price"
echo
echo "  // Your dApp on Chain B simply reads the validated price:"
echo "  function getPriceFromRemote(uint256 sourceChainId, bytes32 poolId) external view returns (PriceData memory) {"
echo "    return priceReceiverResolver.getPrice(sourceChainId, poolId);"
echo "  }"
echo -e "${NC}"
echo -e "✅ ${GREEN}Direct L2-to-L2 messaging via canonical Optimism Messenger.${NC}"
sleep 7

# [0:35 - 1:05] — Demo Simulation
echo -e "\n${BOLD}${GREEN}[RUNNING DEMO SIMULATION]${NC}"
echo -e "⏱️  Simulating L2-to-L2 Oracle Update..."
echo

# Simulate Deployment
echo -e "${CYAN}forge script script/DeployL2L2.s.sol --broadcast ... ${NC}"
sleep 1
echo -e "${BOLD}${CYAN}📦 Deploying PriceReceiverResolver to Chain B...${NC}"
sleep 1
echo "PriceReceiverResolver deployed to Chain B at: 0xBEEF...1234"
sleep 1
echo -e "${BOLD}${CYAN}📦 Deploying PriceSenderAdapter to Chain A...${NC}"
sleep 1
echo "PriceSenderAdapter deployed to Chain A at: 0xCAFE...5678"
sleep 3

# Simulate Sending Message
echo -e "\n${BOLD}${CYAN}[CHAIN A] 🚀 Triggering Price Update Send...${NC}"
echo -e "${CYAN}cast send --private-key \$OWNER_PK ... \$SENDER_ADAPTER_ADDR \"publishPriceData(...)\" ...${NC}"
sleep 1
echo "Transaction sent on Chain A: 0xabc...def"
sleep 2
echo "PriceSenderAdapter calls L2ToL2CrossDomainMessenger.sendMessage(...) targeting Chain B Resolver"
sleep 3

# Simulate Relaying
echo -e "\n${BOLD}${PURPLE}[RELAY] 📨 Relaying Message from Chain A to Chain B...${NC}"
echo -e "(This can be automatic via network relayers OR manual via a service)"
sleep 1
echo -e "${YELLOW}IF MANUAL: Relay Service detects sent message...${NC}"
echo -e "${YELLOW}           Calls L2ToL2CrossDomainMessenger.relayMessage(...) on Chain B${NC}"
sleep 4

# Simulate Receiving Message
echo -e "\n${BOLD}${CYAN}[CHAIN B] ✅ Receiving & Processing Price Update...${NC}"
echo "L2ToL2CrossDomainMessenger calls PriceReceiverResolver.receivePriceUpdate(...) "
sleep 2
echo "Resolver checks msg.sender == MESSENGER_ADDRESS"
sleep 1
echo "Resolver gets original sender (Chain A Adapter: 0xCAFE...) via crossDomainMessageContext()"
sleep 2
echo "Resolver validates sender & timestamp..."
sleep 1
echo "Price data stored successfully on Chain B!"
sleep 3

# [1:05 - 1:15] — Result
echo -e "\n${BOLD}${GREEN}[CHAIN B] === Reading Stored Price ===${NC}"
echo -e "${CYAN}cast call --rpc-url \$RPC_URL_B 0xBEEF...1234 \"getPrice(uint256,bytes32)\" UNCHAIN_CHAIN_ID \$POOL_ID${NC}"
sleep 2
echo "Tick: 12345" # Example Data
echo "SqrtPriceX96: 88765..."
TIMESTAMP=$(date +%s)
echo "Timestamp: $((TIMESTAMP - 30))" # Show slightly older timestamp
echo -e "${BOLD}Price: ${GREEN}~3145.67 USDC/WETH${NC}" # Example Data
echo "Is Valid: true"
sleep 5

# [1:15 - 1:30] — Why It Wins vs Old Approach
echo -e "\n${BOLD}${PURPLE}🏆 COMPARISON: L2-L2 Messenger vs Previous L2Inbox Method${NC}"
echo -e "${YELLOW}┌─────────────────────────┬───────────────────────┬───────────────────────┐${NC}"
echo -e "${YELLOW}│ ${BOLD}Feature                 ${YELLOW}│ ${BOLD}Old L2Inbox Method    ${YELLOW}│ ${BOLD}New L2-L2 Messenger   ${YELLOW}│${NC}"
echo -e "${YELLOW}├─────────────────────────┼───────────────────────┼───────────────────────┤${NC}"
echo -e "${YELLOW}│ ${NC}Relaying Mechanism      ${YELLOW}│ ${RED}Requires Proof Relayer${YELLOW}│ ${GREEN}Autorelay / Simple Tx ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}Sender Verification     ${YELLOW}│ ${RED}Relayer Provided (Event)${YELLOW}│ ${GREEN}Built-in Secure Context ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}Off-Chain Complexity  ${YELLOW}│ ${RED}High (Proofs/Events)  ${YELLOW}│ ${GREEN}Lower (Simpler Relay) ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}On-Chain Validation     ${YELLOW}│ ${RED}Complex Event Decode  ${YELLOW}│ ${GREEN}Simpler (msg.sender)  ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}Protocol Standard       ${YELLOW}│ ${YELLOW}Custom / Semi-Std     ${YELLOW}│ ${GREEN}OP Stack Canonical    ${YELLOW}│${NC}"
echo -e "${YELLOW}└─────────────────────────┴───────────────────────┴───────────────────────┘${NC}"
sleep 8

# [1:30 - 1:35] — Close
echo -e "\n${BOLD}${CYAN}🏁 Demo Complete: AnyPrice L2-to-L2 resolution succeeded using the Optimism SDK pattern.${NC}"
sleep 1
echo -e "\n${BOLD}Project: https://github.com/rbgross/anyprice-oracle-1${NC}"
sleep 4
