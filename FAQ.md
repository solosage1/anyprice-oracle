# ❓ FAQ: OP Superchain Cross-Chain Oracle (Phase 1)

---

<details>
<summary><strong>📡 What is the <code>OraclePriceUpdate</code> event?</strong></summary>

```solidity
event OraclePriceUpdate(
  address indexed source,
  uint256 indexed sourceChainId,
  bytes32 indexed poolId,
  int24 tick,
  uint160 sqrtPriceX96,
  uint32 timestamp
);
```

- Matches the Phase 1 spec in spirit
- Adds a poolId as an extra indexed field for multi-feed support
- Emitted only for fresh data with timestamp validation

---

</details>

---

<details>
<summary><strong>🔐 How is cross-chain authenticity verified?</strong></summary>

Via CrossL2Inbox.validateMessage(_id, keccak256(_data)):
- Verifies proof of the source event
- Rejects invalid or tampered messages
- Ensures the event came from the expected contract on the expected chain

</details>

---

<details>
<summary><strong>🛡️ How is replay protection enforced?</strong></summary>

Two safeguards:
1. processedEvents mapping rejects duplicate events
2. lastProcessedBlockNumber blocks same or earlier block updates per source

</details>

---

<details>
<summary><strong>⏱️ How are timestamp issues handled?</strong></summary>

Source checks:
- Reject unchanged or future timestamps

Resolver checks:
- Rejects stale data (based on freshness + buffer)
- Rejects future timestamps with FutureTimestamp error
- Validates that _id.timestamp <= block.timestamp

</details>

---

<details>
<summary><strong>🧑‍💼 Who is authorized to update or push data?</strong></summary>

- Only the integration contract can call publishPriceData
- Only the resolver's owner can register sources or adjust parameters
- updateFromRemote is public, but validation ensures only legitimate data is accepted

</details>

---

<details>
<summary><strong>⚠️ What happens if multiple events are emitted in one block?</strong></summary>

Only one event per (chain, origin) per block is accepted due to event ID construction.

This is a known limitation for Phase 1. Phase 2 may include batching to address it.

</details>

---

<details>
<summary><strong>⚙️ Is the implementation gas-efficient?</strong></summary>

Yes:
- Compact data types (int24, uint160, etc.)
- Packed storage structs
- Custom errors instead of revert strings
- No historical storage or unbounded loops

Minor gas savings possible by removing debug logs in production.

</details>

---

<details>
<summary><strong>🔀 How does it support multiple price feeds?</strong></summary>

- Each event includes a poolId to uniquely identify a feed
- Resolver tracks data per (sourceChainId, poolId) key
- No need to deploy new contracts per feed

</details>

---

<details>
<summary><strong>🌐 Can it support multiple source chains?</strong></summary>

Yes. Each resolver maintains a whitelist:
```
validSources[chainId][address]
```

Each adapter must be explicitly registered.

</details>

---

<details>
<summary><strong>🔧 Is the system extensible for batching and Phase 2?</strong></summary>

Yes:
- Clean modular design
- Phase 2 can add updateBatchFromRemote() and use OP Messenger for direct L2-to-L2 calls
- No breaking changes required for extension

</details>

---

<details>
<summary><strong>🚀 How do I deploy the system?</strong></summary>

1. Deploy UniChainOracleAdapter and TruncOracleIntegration on the source chain
2. Deploy CrossChainPriceResolver on the destination chain
3. Call registerSource(chainId, adapterAddress) from the resolver's owner
4. Use correct CrossL2Inbox address (default: 0x4200000000000000000000000000000000000022)
5. Optionally deploy UniChainOracleRegistry for metadata tracking

</details>

---

<details>
<summary><strong>🧱 Known Limitations?</strong></summary>

- Only one event per source contract per block
- publishPoolData is publicly callable (could be restricted)
- Event field ordering differs slightly from spec (must align off-chain parsing)

</details>

---

<details>
<summary><strong>📣 Should the destination emit <code>PriceUpdated</code>?</strong></summary>

Optional:
- Helps local consumers listen for updates
- Can be skipped if off-chain infra listens to OraclePriceUpdate directly on source chain

</details>

---

<details>
<summary><strong>📈 What's the roadmap for Phase 2?</strong></summary>

- Batch updates via a new function
- Direct message passing (via OP Messenger)
- Relaxing the one-event-per-block rule with finer granularity

All feasible given the current architecture.

</details>

---

## ✅ Summary
- Compliant with OP Superchain spec (minor field-order deviation noted)
- Secure with cryptographic validation and replay protection
- Efficient gas usage and tight storage
- Modular for multi-chain, multi-feed support
- Phase 2 Ready with batching and messaging support anticipated

---

## 🔗 Deployment Checklist
- Deploy Adapter + Integration on source chain
- Deploy Resolver on destination chain
- Call registerSource for each adapter
- Set correct CrossL2Inbox address
- (Optional) Deploy Registry for adapter metadata 