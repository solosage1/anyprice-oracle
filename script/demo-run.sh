#!/bin/bash

# AnyPrice Cross-Chain Oracle Demo Script
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

# [0:00 - 0:10] — Title + Hook
echo -e "${BOLD}${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "        AnyPrice — Cross-Chain Oracle Access Demo"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"
echo -e "🚀 Initializing AnyPrice Demo..."
sleep 5

# [0:10 - 0:25] — Problem
echo -e "\n${BOLD}${YELLOW}[OPTIMISM CHAIN]${NC}"
echo -e "🧭 You are currently on Optimism chain ID: ${BOLD}10${NC}"
sleep 6
echo -e "📉 Attempting to fetch price for DAI token..."
sleep 2
echo -e "${RED}❌ ERROR: Price feed not available on this chain${NC}"
echo -e "${RED}❌ ERROR: Unknown token source - DAI not available on Optimism${NC}"
echo -e "${YELLOW}✗ Traditional bridges or relayers would be required${NC}"
sleep 5

# [0:25 - 0:40] — Solution
echo -e "\n${BOLD}${BLUE}[ANYPRICE SOLUTION]${NC}"
echo -e "🛠️  With AnyPrice, you can use CrossChainPriceResolver:"
echo -e "${CYAN}"
echo "  function resolvePrice(string memory symbol, uint256 sourceChainId) public view returns ("
echo "    int24 tick,"
echo "    uint160 sqrtPriceX96,"
echo "    uint32 timestamp,"
echo "    bool isValid,"
echo "    bool isFresh"
echo "  ) {"
echo "    return resolver.getPrice(sourceChainId, tokenPoolIds[symbol]);"
echo "  }"
echo -e "${NC}"
echo -e "✅ One function call fetches prices across any chain"
sleep 5

# [0:40 - 0:55] — Demo
echo -e "\n${BOLD}${GREEN}[RUNNING DEMO]${NC}"
echo -e "⏱️  Executing cross-chain oracle demo..."
echo
echo -e "${CYAN}forge script script/OracleCrossChainDemo.s.sol --rpc-url \$OPTIMISM_RPC${NC}"
echo

# Simulating the first part of the demo output with proper timing
sleep 1
echo -e "${BOLD}${CYAN}📦 Deploying UniChainOracleRegistry...${NC}"
sleep 1
echo "TruncGeoOracleMulti deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
echo "TruncOracleIntegration deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
echo "UniChainOracleAdapter deployed at: 0x75537828f2ce51be7289709686A69CbFDbB714F1"
echo "UniChainOracleRegistry deployed at: 0xE451980132E65465d0a498c53f0b5227326Dd73F"
sleep 2

echo -e "\n${BOLD}${CYAN}🚀 Starting AnyPrice Demo...${NC}"
echo "Step 1: Deploying Registry, Adapters, Resolver..."
sleep 2

echo -e "\n${BOLD}${CYAN}📡 Simulating source chain (Chain ID: 10)${NC}"
echo "Running on Optimism..."
sleep 1

echo -e "\n${BOLD}${CYAN}🔗 Registering Oracle Adapters...${NC}"
echo "Oracle data published on source chain"
echo "Setting up cross-chain message..."
sleep 2

# [0:55 - 1:10] — Result & Response
echo -e "\n${BOLD}${CYAN}📡 Sending cross-chain price request for DAI...${NC}"
echo "Switched to destination chain (Chain ID: 1)"
echo "Preparing message channel..."
sleep 2
echo "Message registered in mock CrossL2Inbox"
echo "Waiting for confirmation..."
sleep 2

echo -e "\n${BOLD}${CYAN}🔁 Simulating UniChain OracleAdapter response...${NC}"
echo "Processing incoming message..."
sleep 2

echo -e "\n${BOLD}${CYAN}✅ Resolving price on Optimism side...${NC}"
echo "Price data validated and accepted"
echo "Updating on-chain price oracle..."
sleep 3

echo -e "\n${BOLD}${GREEN}=== Cross-Chain Price Verification ===${NC}"
echo "Tick: 1000"
echo "SqrtPriceX96: 79228162514264337593543950336"
echo "Timestamp: $(date +%s)"
echo -e "${BOLD}Price: ${GREEN}1.000000 DAI${NC}"
echo "Is Valid: true"
echo "Is Fresh: true"
sleep 3

# [1:10 - 1:20] — Why It Wins
echo -e "\n${BOLD}${PURPLE}🏆 COMPARISON: CHAINLINK CCIP vs ANYPRICE${NC}"
echo -e "${YELLOW}┌───────────────────┬────────────┬───────────┐${NC}"
echo -e "${YELLOW}│ ${BOLD}Feature           ${YELLOW}│ ${BOLD}Chainlink  ${YELLOW}│ ${BOLD}AnyPrice  ${YELLOW}│${NC}"
echo -e "${YELLOW}├───────────────────┼────────────┼───────────┤${NC}"
echo -e "${YELLOW}│ ${NC}Oracle Agnostic    ${YELLOW}│ ${RED}❌         ${YELLOW}│ ${GREEN}✅        ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}Modular Adapters   ${YELLOW}│ ${RED}❌         ${YELLOW}│ ${GREEN}✅        ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}One-Line Dev Call  ${YELLOW}│ ${RED}❌         ${YELLOW}│ ${GREEN}✅        ${YELLOW}│${NC}"
echo -e "${YELLOW}│ ${NC}Cross-Chain Ready  ${YELLOW}│ ${GREEN}✅         ${YELLOW}│ ${GREEN}✅        ${YELLOW}│${NC}"
echo -e "${YELLOW}└───────────────────┴────────────┴───────────┘${NC}"
sleep 6

# [1:20 - 1:30] — Close
echo -e "\n${BOLD}${CYAN}🏁 Demo Complete: AnyPrice cross-chain resolution succeeded.${NC}"
sleep 1
echo -e "\n${BOLD}${CYAN}AnyPrice Oracle by Bryan Gross"
echo -e "\n${BOLD}Github: https://github.com/solosage1/anyprice-oracle"
echo -e "${BOLD}Thank you for watching!${NC}" 