# ERC-76xx Refinement and Benchmarking Brief

**TL;DR (1-minute view)**

* **What it is:** ERC-76xx is a draft Ethereum standard from Solo Labs that defines a *versioned, chain-agnostic payload* for pushing time-sensitive oracle data across L1↔L2 and rollup↔rollup boundaries.
* **Why it matters:** Existing oracle APIs (EIP-2362, 7726) stay on one chain; general cross-chain standards (EIP-5164, Bedrock CXM) ignore "freshness." ERC-76xx adds an explicit *valid-until/timestamp field* enabling rollups to receive data with clear freshness guarantees via secure, established channels.
* **How it fits:** For OP-Stack chains (Version 1.0), it RECOMMENDS the Superchain Interop Messenger (L2ToL2CrossDomainMessenger) as the default, low-latency transport for OP-Stack ↔ OP-Stack communication. It is also designed to be bridge-agnostic for other chains or future extensions, remaining *beacon-root-friendly* (EIP-4788) and CCIP-Read-complementary.
* **Core refinements:**

  1. MUST include freshness + chain-ID fields.
  2. For OP-Stack v1.0, RECOMMENDS the Superchain Interop Messenger (SIM) using `sendMessage(uint256 _destination, address _target, bytes memory _message)` for L2-L2 transport. For other chains/future extensions, SHOULD use EIP-712 signatures where applicable.
  3. NICE-TO-HAVEs: governance hooks, ZK-proof extension point (for future extensions), unified naming.
* **Key differentiator:** A key open standard aiming to provide time-sensitive data to rollups with verifiable freshness, leveraging the highest security transport available (e.g., SIM for intra-Superchain by default; canonical CXM only when L1 is involved.). Future extensions may explore a wider range of speed/finality trade-offs.

## Introduction

ERC-76xx is a proposed Ethereum standard (currently in draft by Solo Labs) that aims to enable
trust-minimized delivery of time-sensitive data across chains, particularly to and from rollups. In an
ecosystem crowded with oracle interfaces and cross-chain messaging protocols, ERC-76xx seeks to fill a
critical gap: providing fresh, reliable data on Layer-2 networks within strict time bounds without
sacrificing security. This brief benchmarks ERC-76xx against prior related standards – from pull-based
oracle APIs like EIP-2362
github.com
 to cross-chain execution frameworks like EIP-5164
eips.ethereum.org
 – as
well as the Superchain Interop Messenger (SIM) (per specs.optimism.io). We map ERC-76xx's positioning
in the landscape, identify overlaps or conflicts, and highlight unique problems it solves for rollups.
Finally, we propose concrete spec-level refinements with clear MUST/SHOULD/NICE-TO-HAVE classifications,
present key differentiators for public messaging, and include a security risk register and technical
appendix with relevant calldata/gas benchmarks.
SIM provides 1-block latency across the Superchain while still falling back to L1 finality if reorgs exceed the block-safety window.

## Landscape: Oracles and Cross-Chain Standards

### On-Chain Oracle Interfaces (EIP-2362, EIP-7726)

Ethereum's earliest oracle standards focused on how
contracts retrieve off-chain data values. EIP-2362 ("valueFor") defines a simple pull-based interface
for numeric oracles, where a consumer contract calls valueFor(bytes32 id) and receives an integer
value, a timestamp, and a status code
github.com
. All EIP-2362 providers use the same ID convention so
that different oracles refer to the same data series
github.com
.[^1] However, EIP-2362 assumes a
single-chain context – it does not account for cross-chain sources or the latency of obtaining data
from L1 versus L2. More recently, EIP-7726 ("Common Quote Oracle") standardized an API for asset price
feeds (e.g., in draft-04 of the EIP): it introduces `quote(uint256 baseAmount, address base, address quote)` which returns how much of quote asset equals
a given baseAmount of base asset
eips.ethereum.org
eips.ethereum.org
. This forces compliant protocols to use explicit
token amounts (e.g. 1e6 USDC in ETH terms) instead of floating price factors, improving consistency
eips.ethereum.org
.
Like EIP-2362, EIP-7726 focuses on on-chain oracle adapters and does not inherently solve cross-chain
delivery – it presumes the data feed is available locally on the chain where it's queried.

### Off-Chain Data via CCIP-Read (EIP-3668)

To mitigate on-chain storage costs and enable Layer-2
integration, EIP-3668 (CCIP-Read) provides a pattern for fetching data from an external source in a
verifiable way. Instead of returning a value directly, a smart contract can revert with an
OffchainLookup error that includes URLs and call data
eips.ethereum.org
. A client (wallet or RPC) that
supports CCIP-Read will catch this revert and perform an off-chain lookup (e.g. an HTTP GET) to retrieve
the requested data, then invoke a callback function on-chain with the response
eips.ethereum.org
. The contract
is responsible for validating the response (often via signature or merkle proof) before using it
eips.ethereum.org
eips.ethereum.org
.
This mechanism effectively delegates the data query to an off-chain "oracle server" while keeping
the verification on-chain and transparent to users. CCIP-Read is powerful for reading from layer-2 or
off-chain databases (ENS has adopted this for Layer-2 name records
basics.ensdao.org
), but it requires off-chain
infrastructure (the "CCIP gateway") and doesn't define a standard for writing or pushing data across
chains in real-time. Efforts like CCIP-Write are emerging to extend this concept to transactions,
combining EIP-3668 with off-chain EIP-712 signatures for integrity
ethereum-magicians.org
. ERC-76xx differs in that
it targets a standardized on-chain interface for time-sensitive data delivery, rather than relying on
external gateways for each use case.

### Cross-Chain Execution and Messaging (EIP-5164, EIP-7092)

As DeFi became multi-chain, standards for
general message passing arose. EIP-5164 (Cross-Chain Execution) defines a generic interface for
contracts on one EVM chain to call contracts on another via a message dispatcher on the source and a
message executor on the destination
eips.ethereum.org
eips.ethereum.org
. The dispatcher emits an event carrying the
call details (target chain, contract, function data, etc.), which a bridge or relayer transports to the
target chain's executor to invoke the call
eips.ethereum.org
eips.ethereum.org
. Importantly, EIP-5164 is bridge-agnostic –
it doesn't mandate how messages get across (could be native bridge, third-party, etc.), only that any
compliant bridge expose the same send/execute interface
qualitax.gitbook.io
qualitax.gitbook.io
. This improves reuse
of cross-chain code and abstracts over different security/speed trade-offs. However, EIP-5164 treats all
messages uniformly; it doesn't have a notion of message expiry or data freshness. A related standard,
EIP-7092 (Financial Bonds), even includes an optional (and currently draft) cross-chain module for bond tokens, allowing a
bond contract to specify a destination chain and contract when transferring tokens across chains
eips.ethereum.org
eips.ethereum.org
.
That interface essentially wraps a cross-chain message send within a token transfer function. The
existence of such ad-hoc cross-chain extensions underscores the need for a unified approach. ERC-76xx
can be seen as targeting a similar layer as EIP-5164 – a chain-agnostic message format – but specialized
for oracle data updates with timing constraints.

### L2 ↔ L2 (Superchain Interop Messenger)

For OP-Stack chains, the Superchain Interop Messenger (SIM) provides a standardized and low-latency pathway for L2-to-L2 communication. The SIM leverages a `CrossL2Inbox` contract on the destination chain and the `L2ToL2CrossDomainMessenger` on the source chain. This architecture typically enables 1-block latency for messages between Superchain rollups.[^SIM_Compatible_Tokens] The security of SIM relies on block-safety levels (typically `block-safety-level = 1` by default, though configurable by chains); if a source chain reorgs beyond this defined safety window, both chains revert together if the safety window is exceeded; eventual finality is via L1. Use of SIM also typically implies an "OP Supervisor" or equivalent mechanism for overseeing and relaying messages; importantly, the op-supervisor only observes and forwards logs; it never signs or re-orders them. This transport is the recommended default for ERC-76xx on OP-Stack chains for intra-Superchain communication. For L1 ↔ L2 communication, or when broadcasting to Ethereum mainnet, the canonical Bedrock messenger remains a fallback profile.[^SIM_Explainer][^SIM_Message_Passing][^SIM_Reorg_Awareness]

### Beacon Chain Root as Oracle (EIP-4788)

An emerging piece of the interoperability puzzle is EIP-4788,
which will expose the Ethereum beacon chain's state root (specifically, the previous beacon-block root, typically one epoch or ≈ 6.4 min old) inside the EVM
consensys.io
. The contract implementing EIP-4788 stores approximately one day of historical roots in a ring buffer. In essence,
EIP-4788 is an enshrined oracle for Ethereum's consensus state
consensys.io
, allowing smart contracts
to access a recent beacon block root. This is particularly useful for verifying finality of checkpoints
or bridging data from Ethereum to other domains (e.g. proving to an L2 that some event is finalized on L1
via the beacon root). While not directly a cross-chain messaging protocol, EIP-4788 provides a trusted
anchor point (the beacon chain) that could help time-sensitive data attestation. For instance, a rollup
oracle might include a beacon block timestamp or root to prove recency of its data. ERC-76xx can leverage
such primitives (as available) to enhance trust – e.g. by anchoring L2 data to a beacon root snapshot to
prove it's at least as recent as a certain epoch.

## ERC-76xx Positioning and Comparative Analysis

### Filling the Gap

ERC-76xx positions itself at the intersection of oracle data feeds and cross-chain
messaging. Unlike pure oracle standards (2362, 7726) which assume data is readily available on-chain,
ERC-76xx recognizes that on a rollup, the authoritative data might reside on another chain (often L1)
and that fetching it quickly is non-trivial. Conversely, unlike general cross-chain call standards
(5164) that handle arbitrary function calls, ERC-76xx is purpose-built for data payloads that lose
value over time. Examples include price oracles for fast-moving markets, volatility metrics, or any
feed where a 7-day-old value is effectively useless. By specializing, ERC-76xx can introduce notions
of validity period, preferred transport, and data-specific verification that general message passers
lack.

### Overlap with Existing Standards

There is naturally some overlap with the above standards:

#### Interface overlap
At the simplest, ERC-76xx might offer a function like getLatest(bytes32 id) or
readData(bytes key) similar to valueFor from EIP-2362. If so, consumers of ERC-76xx could look
superficially like they are using an oracle API. The difference is under the hood – an ERC-76xx provider
could be pulling data from an L1 contract or another rollup, rather than aggregating off-chain sources.
ERC-76xx should therefore ensure its interface either extends EIP-2362 (to maintain familiarity) or uses
distinct naming to avoid confusion. (One possibility is to integrate with the ID scheme of 2362, so that
the same bytes32 id used in Tellor/Witnet oracles denotes the same feed in ERC-76xx, avoiding duplicate
identifiers.)

#### Message transport overlap
ERC-76xx will inevitably use some cross-chain transport. It could use the
OP Stack messenger where available, or a third-party bridge, or EIP-5164 adapters. In fact, an ideal
implementation might implement IERC5164 in the background. However, conflicts could arise if both
standards are implemented on a contract. Care must be taken that an ERC-76xx message doesn't unintentionally
double-dispatch via 5164 and a rollup messenger. A refinement might be needed to clearly delineate when
to use which mechanism (possibly via network identifiers or chain-specific gateways).

#### CCIP-Read interplay
ERC-76xx and EIP-3668 can complement rather than conflict. For instance, an
ERC-76xx data provider on L2 might use CCIP-Read to fetch data from L1 off-chain in the process of
serving a user query. But if ERC-76xx's goal is on-chain fulfillment, it would more likely push updates
to L2 proactively (so that data is available on-chain without an external lookup at query time). This
proactive push model is something CCIP-Read alone doesn't handle. The standards aren't mutually exclusive:
ERC-76xx could specify that if data is stale, consumers could fall back to a CCIP-Read approach as a
SHOULD-level recommendation.

#### Cross-chain token standards
While ERC-76xx is not a token standard, EIP-7092's cross-chain transfer
mechanism for bonds highlights a pattern of embedding chain IDs and target addresses in function calls
eips.ethereum.org
.
ERC-76xx similarly will need to deal with identifying source and destination chains (e.g., to say "this
L2 update came from mainnet at block X"). Overlap here is minimal because ERC-76xx's payload is data, not
tokens, but any naming of fields like destinationChainID should align with conventions (e.g. using
the same chain ID numbering as EIP-7092 and EIP-5164 for consistency).

#### Optimism's Messenger vs. ERC-76xx
The Superchain Interop Messenger (SIM) is an implementation, not a standard, but it's
widely used across the OP Stack. If ERC-76xx defines its own cross-domain message format for data, there's a risk of
duplicating what SIM already provides. Overlap exists in that both define a message structure (nonce,
sender, target, data, etc.). ERC-76xx operates at the application layer; its specialized fields (like freshness or expiry timestamps) are contained *within* the `messageData` payload of the underlying SIM call, not as modifications to the SIM header or contracts themselves. The ERC should strive to be compatible – e.g., perhaps recommending that on
Optimism-class rollups, an ERC-76xx message should be sent via the `L2ToL2CrossDomainMessenger` contract (rather
than a custom bridge). This avoids conflict and leverages the security of the L2-provided mechanism.
Where L1 finality is paramount or for L1-L2 messages, ERC-76xx could specify the canonical Bedrock CXM as an alternative, but it
must carefully outline the trust model for that (see Unique Problems below).

### Identified Gaps and Conflicts

No existing standard cleanly addresses fast, trust-minimized data updates to rollups:
* EIP-2362/7726 do not consider cross-chain latency or validity windows, so using them for rollups
  would either introduce race conditions (data becomes outdated) or rely entirely on the oracle's honesty
  about freshness.
* EIP-5164 provides a container to ship a message, but doesn't say when or how quickly it must be
  delivered. Nor can a receiving contract easily reject a too-old message without a convention – a gap
  ERC-76xx could fill by including timestamps or expirations in the message format.
* The Superchain Interop Messenger (SIM) offers low-latency L2-L2 communication, but applications still need a standard like ERC-76xx to define the *payload* for time-sensitive oracle data, including freshness guarantees. Canonical Bedrock CXM enforces a ~7-day delay for L2→L1 messages. For L1→L2 messages, while timely, it adheres to the canonical security model. ERC-76xx Version 1.0, for OP-Stack chains, RECOMMENDS SIM for L2-L2 and explicitly commits to the canonical Bedrock model for L1-involved interactions, inheriting its security properties (including any associated delays for L2→L1). Proposals for alternative, faster (and potentially less trust-minimized) schemes for OP-Stack L1 interactions are out of scope for v1.0 and would need to be specified in separate extension profiles with their own security analyses.
* There is potential overlap with Chainlink's Cross-Chain Interoperability Protocol (CCIP) which was
  not an EIP at the time of writing. CCIP is an off-chain service and protocol for cross-chain data and
  token transfers. While not a formal standard in Ethereum, it targets similar goals. A differentiator
  for ERC-76xx is that it is meant to be an open standard without reliance on a single network of
  operators. It should thus clarify how any party can participate in relaying or verifying the data,
  to avoid simply replicating a closed solution.

## Unique Problems Solved by ERC-76xx

### Timeliness with Superchain Interop

The Superchain Interop Messenger (SIM) enables low-latency (typically 1-block) communication between OP-Stack chains. ERC-76xx leverages this by providing a standardized framework to get time-sensitive data where it's needed before it goes stale. For example, suppose an L2 DEX on one OP-Stack chain (e.g., Unichain) needs the latest price of an asset from another OP-Stack chain (e.g., Optimism Mainnet) during a volatility event. ERC-76xx, using SIM as its transport, would allow a standardized push message from Optimism Mainnet to Unichain carrying "Price = $X, valid until time T" with minimal delay. This solves the problem of L2-to-L2 data timeliness in a way that general messengers (which have no notion of data expiry or standardized oracle payloads) do not. The system also provides reorg awareness, meaning if the source chain reorgs past its configured block-safety window (defaulting to 1 block), both chains revert together; eventual finality is via L1.[^SIM_Reorg_Awareness]

* **Super-low-latency rollup-to-rollup price feeds:** SIM lets Optimism Mainnet prices reach Unichain in a single block while preserving fault-proof guarantees.

### Cross-Rollup Data Availability

As multiple rollups proliferate, some data needs to be shared
across them (earning ERC-76xx comparisons to a "broadcast" standard). Consider a multi-chain governance
protocol that runs on several L2s – if one chain computes a critical parameter (e.g. a global debt ratio
or interest rate) that others must know promptly, ERC-76xx offers a route to broadcast that number with
guarantees. It effectively treats certain data as public goods that can be relayed trustlessly via
common L1. In contrast, EIP-2362 or Chainlink oracles would have to separately publish the data on each
chain (incurring duplication and potential inconsistencies). A related new proposal is the Crosschain
Broadcaster standard
ethereum-magicians.org
, which uses storage proofs to let any chain read a message from another.
ERC-76xx's focus on time sensitivity might lead it to favor a simpler approach (perhaps authorized
relayers posting updates) to minimize latency. Still, the problem being solved is unique: ensuring
that "the right now" state on Chain A is reflected on Chain B before it becomes "a while ago".

### Granular Trust and Governance

ERC-76xx aims to enable applications to manage how they balance trust and speed. However, for Version 1.0 implementations on OP-Stack chains, the standard defers to the established security model of the canonical Bedrock Cross-Domain Messenger. This prioritizes safety-over-liveness and trust-minimization by leveraging Ethereum-level security guarantees inherent in the canonical bridge.

While the broader ERC-76xx framework may eventually accommodate various trust models as optional extensions or for use on other (non-OP-Stack) chains – spanning from fully-trusted (e.g., a single permissioned relayer) to fully-trustless (e.g., L1 finality proofs) – these are not part of the v1.0 specification for OP-Stack. For example, future extensions (e.g., an "ERC-76xx-OPT" profile) might define roles like "FastDataReporter" (potentially bonded and subject to slashing) and "DataChallenger" for applications explicitly opting into non-canonical, faster paths after careful consideration of the associated risks and security assumptions.

For v1.0 on OP-Stack, the focus is on providing time-sensitive data with verifiable freshness through the most secure, canonical mechanism available. Applications requiring different trust assumptions (e.g., for ultra-low latency use cases not primarily targeted by the Superchain mission) would need to await or propose such specific extension profiles, which would require their own rigorous security analysis and governance approval separate from the core ERC-76xx standard.

### Superchain Alignment for L2s

For OP-Stack rollups (the Superchain), ERC-76xx solves
the issue of how to inject external data from other L2s within the Superchain without breaking the layer's security model. SIM offers robust and fast L2-to-L2 communication. ERC-76xx could specify a pattern whereby an L2 contract consumes data
from an ERC-76xx provider contract on its own L2, which itself is fed by another L2 via SIM, or by an L1 messenger, or by a governed oracle.
By standardizing this pattern, all OP Stack chains could adopt a common approach to fast data sharing within the Superchain. This
means developers building on Base, Zora, OP Mainnet, Unichain, etc., would have a unified interface to retrieve,
say, the latest cross-chain price feed from another Superchain L2, knowing it's updated promptly. It
essentially solves "How do we get L2 state from another L2 in near real-time within the Superchain?" – something not solved out of
the box today by a payload-specific standard like ERC-76xx.

## Spec-Level Refinements and Recommendations

Based on the above analysis, we propose the following refinements to the ERC-76xx draft specification.
Each item is marked as MUST, SHOULD, or NICE-TO-HAVE to indicate priority:

* **RECOMMENDED DEFAULT TRANSPORT (OP-Stack Chains):** Use the Superchain Interop Messenger (L2ToL2CrossDomainMessenger) for L2→L2 data updates. L1 ↔ L2 canonical Bedrock CXM remains a fallback profile (e.g., when broadcasting to Ethereum mainnet) but is not the default for intra-Superchain messaging.
* **MUST:** Include a Data Freshness Field. The standard message format should include either an explicit
  timestamp (when the data was fetched or signed) or an expiry time after which the data is considered
  stale. This allows receiving contracts to reject or ignore outdated messages. For example, a price
  update might carry validUntil = UNIX time + 5 minutes. If the message arrives after that, the target
  can skip applying it. Without this, there is ambiguity about data validity and no improvement over
  existing oracles. (EIP-2362 provides a timestamp with each value
  github.com
  ; ERC-76xx should do the same
  and enforce its use in consumers' logic.)
* **MUST:** Define Standard Chain Identifier Usage. To avoid confusion in cross-chain calls, ERC-76xx
  messages and interfaces should use the same uint256 chainId values as Ethereum's chainid opcode
  (EIP-155) for identifying chains. If a field like sourceChainID or destinationChainID exists (as in
  ERC-7092's cross-chain functions
  eips.ethereum.org
  ), it must align with these standard IDs. This ensures
  compatibility with EIP-5164 (which will likely use chain IDs too) and prevents misrouting. The spec
  should clearly state that chain IDs are part of the message signature to prevent replay of a message
  meant for one network on another.
* **MUST:** Include `_destination` (formerly `destinationChainId`) in the payload. Given that the Superchain Interop Messenger (SIM) is inherently designed for multi-L2 communication, the ERC-76xx payload MUST include a `_destination` field. This allows the `L2ToL2CrossDomainMessenger` to correctly route the message and ensures the ERC-76xx message is processed on the intended destination chain.
* **SHOULD:** Leverage EIP-712 for Off-Chain Signatures. If future extensions of ERC-76xx, or its use on non-OP Stack chains, allow or encourage any off-chain
  components (like a relayer network or oracle signers for alternative transport mechanisms), it should adopt EIP-712 structured data signing
  for any signed payloads. EIP-712 provides domain separation and a clear schema for signing data
  eips.ethereum.org
  ,
  which is critical to avoid replay attacks across domains. Concretely, the spec might define a Typed Data
  structure named DataUpdate with fields (sourceChainID, dataID, value, timestamp, etc.), and require
  that any off-chain signature conform to that. This makes verification on-chain straightforward and uses
  battle-tested libraries and wallet support (Metamask, ethers.js, etc., all support EIP-712 signing).
* **INTEGRATION WITH SUPERCHAIN INTEROP MESSENGER (OP-Stack Default L2-L2 Profile):** When using the recommended default transport profile for L2-L2 communication on OP-Stack chains, ERC-76xx provider contracts SHOULD send data via the `L2ToL2CrossDomainMessenger.sendMessage` function. The ERC-76xx specific fields like freshness or expiry timestamps are part of the application-level calldata (`message` argument to `sendMessage`), not a modification to SIM's headers or contracts. The format of the message data payload MUST match the ERC-76xx struct. This ensures that this profile utilizes the most secure and audited delivery mechanism available for L2-L2 messages on these chains. For L1 interactions (L1→L2 or L2→L1 messages relayed via L1), the spec SHOULD refer to the canonical Bedrock CXM, and MUST clarify that the typical ~7-day fraud proof window delay applies for L2→L1 when using this canonical path.
* **SHOULD:** Emit `SentMessage` hash as a unique nonce/ID. The Superchain Interop Messenger emits a `SentMessage` event containing a hash that uniquely identifies the message. ERC-76xx implementations SHOULD use this hash (or a derivative) as a unique identifier or nonce for the oracle update. This leverages SIM's built-in replay protection mechanisms and provides a clear way to track message status.
* **SHOULD:** Document block-safety-level assumptions. Implementations using SIM SHOULD clearly document their assumptions regarding block-safety levels and provide recommendations for confirmation depths. This is crucial for consumers to understand the trade-offs between latency and finality, especially for "critical" feeds (e.g., those triggering liquidations) versus "non-critical" feeds. Guidance should align with Optimism's reorg-awareness documentation.[^SIM_Reorg_Awareness]
* **SHOULD (for non-OP Stack chains or future extensions/profiles):** Compatibility with EIP-5164 Dispatcher/Executor. For chains not part of the OP Stack, or for future extensions/profiles of ERC-76xx that might define alternative transport mechanisms, the ERC-76xx
  contract could implement the MessageDispatcher interface from EIP-5164 for sending its updates, and
  the MessageExecutor on the receiving side
  eips.ethereum.org
  . This would make ERC-76xx updates recognizable
  to any bridges that support EIP-5164, essentially for free. It aligns with the bridge-neutral philosophy.
  If full interface implementation is too much overhead, the spec at least should not conflict – e.g.
  reserve messageId or event names similarly to avoid collisions.
* **NICE-TO-HAVE:** Integration with Future OP Stack Interoperability Mechanisms. The Optimism ecosystem is continuously evolving. For instance, OP Labs is developing an Attestation Bus, a lightweight storage-proof broadcaster for Superchain interoperability. When such mechanisms become standardized and available, ERC-76xx messages (particularly those intended for broad Superchain consumption) SHOULD be serializable into these channels (e.g., as a specific message type like `0x02` if the Attestation Bus defines such). This aligns ERC-76xx with the broader Superchain vision and avoids redundant infrastructure. Implementers should monitor OP Stack developments for such integration opportunities.
* **NICE-TO-HAVE:** Governance Hooks for Data Providers. To enhance security, the standard could allow
  each ERC-76xx data feed contract to have a configurable list of authorized publishers and possibly a
  governance delay. For instance, a feed might be upgradable (via a DAO vote) to change who can post
  updates or to switch the transport mechanism if a bridge is deprecated. While governance mechanisms are
  often application-specific, providing a recommended template (such as OpenZeppelin's AccessControl or a
  timelock on critical parameter changes) would help implementers avoid mistakes. This is not an absolute
  requirement of the spec, but outlining it as a best practice (SHOULD) is prudent given the varying trust
  models. Specifically for OP Stack chains, any such governance mechanism should consider integration with the chain's prevailing security model; for example, the same `isPausedBySecurityCouncil()` check (or equivalent mechanism as defined by the specific Superchain's governance) SHOULD gate `receiveUpdate()` (or the primary data-receiving function of an ERC-76xx implementation) so oracle pushes automatically pause during L2 incidents managed by the Security Council. The goal is that no single operator should have unchecked power over a critical cross-chain feed
  without some ability for oversight or upgrade, and that on-chain safety mechanisms are respected.
* **NICE-TO-HAVE:** Unified Naming and Alignment. During the draft review, check all function and event
  names against existing standards to avoid confusion. For example, if the spec currently calls the update
  function pushData, consider whether relayData or sendData would better convey its cross-chain nature
  (also aligning with terms like sendMessage in Bedrock
  specs.optimism.io
   or dispatchMessage in EIP-5164).
  Similarly, event names like DataReceived or DataRelayed could be standardized so dApp developers
  instantly recognize what happened. These naming tweaks improve developer experience and reduce errors.
* **NICE-TO-HAVE:** Extensibility for Future Proofs. Looking forward, the spec could include an extension
  point for validity proofs (in case some rollups move to faster finality via zk-proofs). For instance, an
  optional field for a ZK proof or commitment could be added to the message structure, which if present
  indicates the data comes with a cryptographic proof. This way, when technology permits, a rollup might
  accept a proof-included message near-instantly (no 7-day wait) and verify it on-chain. This is forward-
  looking and not immediately required, but including a placeholder or a versioning mechanism (so that
  ERC-76xx v2 can add proofs) would prevent the standard from being short-lived.

Each of these refinements is aimed at making ERC-76xx more robust and easier to integrate: MUST items
address fundamental correctness and interoperability, SHOULD items improve security and adoption
likelihood, and NICE-TO-HAVE items provide future flexibility without bogging down the core spec.

## Key Differentiators of ERC-76xx

Solo Labs can highlight the following unique selling points of ERC-76xx in public communications, keeping in mind the collaborative nature of standards development and Optimism's ongoing work on initiatives like their Bridge Neutrality and Standardised Proofs roadmap:
* 🚀 **Oracle-Specific Standard for Real-Time Data:** ERC-76xx is a pioneering oracle-specific Ethereum standard that formalizes the inclusion of time-to-freshness directly into the payload.
* 🔗 **Built for Superchain Interop (SIM default) — trust-minimized, 1-block cross-rollup latency.** For OP-Stack L2-L2 communication, ERC-76xx's primary profile recommends the Superchain Interop Messenger, ensuring low latency and alignment with the Superchain vision. Its design also supports the canonical Bedrock CXM for L1-involved transports and can accommodate other transports for non-OP chains or future extensions/profiles.
* 🛡️ **Trust-Minimized Default Profile (OP-Stack):** By defaulting to SIM for L2-L2 messages and Bedrock CXM for L1-involved messages on OP-Stack chains, ERC-76xx's primary profile inherits Ethereum-level security (for L1 interactions) and OP-Stack's established L2 security for intra-Superchain messages, without introducing new trust assumptions for these primary use cases. Future extensions or alternative profiles for other contexts might explore a broader range of trust assumptions, but these would be separate, opt-in profiles.
* 🤝 **Unified Interface:** ERC-76xx unifies concepts from multiple prior EIPs (oracle queries, cross-chain
  calls, off-chain reads) into a single interface. Developers integrate once and gain access to data
  feeds that work across Ethereum, L2s, and sidechains, with no custom adapters per chain for the core data format.
* ⚙️ **Governable and Upgradeable (within Canonical Constraints for OP-Stack v1.0):** The standard anticipates the need for governance hooks. For OP-Stack v1.0, this operates within the security and governance framework of SIM, Bedrock CXM, and the Superchain (e.g., respecting Security Council pauses). Future extensions or alternative profiles might define more elaborate governance for alternative transport mechanisms.
* 📊 **Gas and Bandwidth Optimized:** By standardizing the data format and transport (via SIM for L2-L2 and Bedrock CXM for L1-involved messages on OP-Stack v1.0), ERC-76xx enables
  batching and efficient use of calldata. Preliminary benchmarks show that cross-chain data updates can be
  delivered with minimal overhead beyond the raw data size (see Appendix), making it cost-effective even
  as frequency scales.

(Above bullet points can be used in blogs, documentation, or tweets to succinctly communicate what
makes ERC-76xx different.)

## Security Risk Register

Implementing ERC-76xx entails several risks which should be catalogued and managed. The following register considers risks applicable to the standard in general. For Version 1.0 implementations on OP-Stack chains, which primarily use the Superchain Interop Messenger (SIM) for L2-L2 communication and the canonical Bedrock Cross-Domain Messenger for L1-involved communication, certain risks (particularly those related to alternative, non-canonical transport layers or off-chain signers) are largely mitigated by the inherent security of these messengers. However, these risks remain relevant for potential future ERC-76xx extensions that might define such alternative paths, or for implementations on non-OP-Stack chains using different transport mechanisms. It is important to note that Superchain Interop, including SIM, is in active development and not yet considered production-ready at the time of writing; implementers should consult the latest Optimism documentation for current status and recommendations.

* **Stale Data / Timing Risk:** A data update might arrive or be executed after its intended validity
  window, potentially leading contracts to act on outdated information. Mitigation: Include
  timestamps/expiries in messages and have receivers check them (per spec). If an update is too old, it
  should be ignored. Also, design the system so critical updates are sent with some time margin or
  repeated if needed.
* **Oracle Manipulation:** This risk primarily concerns scenarios where data can be injected or altered by non-canonical actors (e.g., via a compromised fast-path relayer or a malicious signer quorum in a hypothetical future extension or a non-OP-Stack implementation). Mitigation for such scenarios would typically involve: requiring multiple
  independent signers (quorum) for fast updates, using a challenge period where conflicting proof can
  overwrite false data, and aligning incentives by slashing or economic security (like a bond posted by relayers
  that is slashed on bad data). Additionally, limiting the scope (e.g., cap how far the data can deviate) can help catch anomalies. For ERC-76xx Version 1.0 on OP-Stack chains using SIM or Bedrock CXM, this risk is significantly minimized as data integrity relies on the security of the source chain and the respective messenger; manipulation would require compromising the source L1/L2 itself or the messenger contracts.
* **Replay Attacks:** A valid data message on one chain could be replayed on another chain, or the same
  message applied twice, if not uniquely identified. Mitigation: Use chainId and nonce in the message.
  Each update ID should be unique (perhaps a combination of source chain, sequence number, and feed ID).
  The spec should mandate nonce tracking to prevent replays. EIP-5164's messageId scheme (unique across
  dispatchers) can be leveraged
  eips.ethereum.org
  .
* **Reorg-Awareness Risk (NEW):** With low-latency L2-L2 messaging via SIM, there's a risk associated with source chain reorgs. If the source chain reorgs past the block containing the initiating transaction after the message has been processed on the destination chain, inconsistencies can arise. Mitigation: SIM incorporates block-safety levels (defaulting to 1 block, but configurable by chains). If a reorg exceeds this safety margin, both chains revert together; eventual finality is via L1. Applications using ERC-76xx over SIM MUST be aware of these characteristics and the `block-safety level` parameter. Critical applications SHOULD wait for additional confirmations on the source chain beyond the 1-block SIM latency if immediate finality is paramount, or be designed to handle potential rollbacks. Documentation should clearly state these assumptions and recommendations.[^SIM_Reorg_Awareness]
* **Bridge Contract Bugs:** The underlying transport (e.g., Superchain Interop Messenger's `CrossL2Inbox` and `L2ToL2CrossDomainMessenger` contracts, or the canonical Bedrock L1–L2 CXM) could have a
  vulnerability, leading to loss or duplication of messages or exploits. Mitigation: Favor well-
  audited, widely used transports (like SIM and Bedrock CXM) whenever possible. If a custom
  bridge is used, get thorough audits and consider fail-safes (pauses, rate-limits on messages) to
  contain any issues. The standard can recommend only using battle-tested bridges for production.
* **DoS via Spamming:** An attacker could spam a target contract with a flood of data messages
  (especially if open participation in broadcasting is allowed), causing high gas use or state bloat.
  Mitigation: Introduce rate limiting or economic cost to sending messages. For instance, require a
  minimal bounty or fee for each cross-chain message (as Superchain Interop Messenger does with bond deposits). The
  receiving contract can also impose access control (only accept messages from a designated ERC-76xx
  provider contract). Additionally, on-chain filters could drop messages that don't change the data
  significantly (to avoid redundant writes).
* **Consistency Across Chains:** Different listeners on different chains might receive a series of
  updates in different orders or timings, causing inconsistent state (e.g., Chain A got two quick
  updates, Chain B only got one due to delay). Mitigation: The standard should clarify the expected
  behavior for multi-target broadcasts. Possibly sequence numbers for each feed ensure receivers apply
  updates in order. If an update is missed, the next one could include a cumulative proof or state so
  that eventual consistency is reached. Testing on multiple networks and providing best-practice guidance
  will help implementers avoid edge-case issues.
* **Governance Keys Compromise:** If governance or upgrade keys (to change data providers or config) are
  compromised, attackers could change critical parameters or redirect data flow. Mitigation: Encourage
  decentralizing governance (multisigs, timelocks, DAO votes) and possibly using fail-safe mechanisms
  (e.g., emergency off-switch that reverts to L1 truth if something is clearly wrong). Document in the
  spec which parameters are governance-controlled and suggest security practices around them.

This register should be revisited periodically. As ERC-76xx matures through audits and testnet trials,
new risks may be identified (or some of the above mitigations refined). The goal is to ensure that
adopting this standard does not introduce unacceptable vulnerabilities relative to the status quo.

## Technical Appendix: Call Data Formats and Gas Benchmarks

### Example Cross-Chain Message Format

Under the hood, an ERC-76xx data update from a source L2 to a destination L2 on the OP-Stack (Superchain)
utilizes the Superchain Interop Messenger (SIM). The source L2 contract calls `L2ToL2CrossDomainMessenger.sendMessage`.
If we tailor this to ERC-76xx, the `_message` bytes would contain the specific feed update (e.g., encoded as
(bytes32 id, int256 value, uint64 timestamp) using ABI encoding). The `_target` would be the ERC-76xx
receiver contract on the destination L2 that knows how to parse and store the data, and `_destination` would specify the target L2's chain ID.
Below is a hypothetical encoding example:

```solidity
// Pseudocode: Source L2 sender calls L2ToL2CrossDomainMessenger with the data update
// interface IL2ToL2CrossDomainMessenger {
//     function sendMessage(uint256 _destination, address _target, bytes memory _message) external returns (bytes32);
// }

bytes memory erc76xxPayload = abi.encode(id, value, timestamp); // Application-level payload
bytes memory fullMessage = abi.encodeWithSelector(
    ERC76xx_Dest_L2_Contract.receiveUpdate.selector, 
    id, 
    value, 
    timestamp
    // Potentially other ERC-76xx specific fields like sourceFeedId, originalSourceChainId if different from msg.context.sourceChainId
);

// Actual call to SIM
// Assuming L2ToL2CrossDomainMessenger_Optimism is an instance of the messenger predeploy
bytes32 msgHash = L2ToL2CrossDomainMessenger_Optimism.sendMessage(
    DESTINATION_UNCHAIN_CHAIN_ID, // e.g., Unichain's chain ID passed as _destination
    ERC76xx_Dest_L2_Contract_Address, // Address of ERC-76xx receiver on Unichain passed as _target
    fullMessage // The actual message to be executed on the target contract
);
```

On the destination L2 (e.g., Unichain), the `receiveUpdate` function (selector shown above) would be called by that L2's `L2ToL2CrossDomainMessenger` instance (acting as the `msg.sender` to `ERC76xx_Dest_L2_Contract`). This function would verify that `msg.sender` is the authentic `L2ToL2CrossDomainMessenger` on its chain. It would then decode the source chain ID from the SIM context (e.g., via a helper on the `L2ToL2CrossDomainMessenger` or passed in `receiveUpdate` if SIM evolves to provide it directly) and potentially the original sender on the source L2 if needed, and then update storage with the new value if the timestamp is within allowed freshness and other ERC-76xx specific checks pass. The `msgHash` can be used for replay protection if the ERC-76xx implementation requires it (see Spec-Level Refinements).

### Calldata Size

The size of a single data update message is quite small. In the example `(bytes32 id, int256 value, uint64 timestamp)`:
`id` is 32 bytes,
`value` (an int256) is 32 bytes,
`timestamp` conceptually 8 bytes (if using uint64). However, in standard ABI encoding (e.g., for function calls like `receiveUpdate(bytes32, int256, uint64)`), a `uint64` will be padded to occupy a full 32-byte word. Thus, for a function call with these three parameters, the payload would be `function_selector (4 bytes) + id (32 bytes) + value (32 bytes) + timestamp (32 bytes) = 100 bytes`. Achieving actual 8-byte usage for the timestamp in the calldata stream would require mechanisms like `abi.encodePacked` or custom serialization (e.g., CBOR), where the data isn't necessarily aligned to 32-byte words for individual parameters. For the purpose of this estimation, we consider the ~100 byte figure based on typical ABI encoding for function calls.
On L1, calldata costs 16 gas/byte for non-zero bytes and 4 gas/byte for zero bytes (post EIP-2028). So 100 bytes, assuming a mix (e.g., ~30% zero bytes for a typical ABI blob), might cost in the range of 1,200–1,600 gas. This is negligible compared to the base cost
of a transaction (21,000 gas) and any L1 execution.

### Gas Cost Benchmarks

* **Cross-Chain via Superchain Interop Messenger (L2-L2):** For OP-Stack to OP-Stack communication using SIM, the costs are entirely on L2. Initiating the message on the source L2 (e.g., calling `L2ToL2CrossDomainMessenger.sendMessage`) costs approximately 27,100 gas. Executing the message on the destination L2 (the `receiveUpdate` call in the ERC-76xx contract) costs approximately 22,100 gas. (Note: These figures exclude the base cost of the L2 transaction itself, e.g., 21,000 gas, as per Optimism documentation conventions for estimating intrinsic costs of operations). This execution cost might be zero for the user if an autorelayer service covers it. Total latency is typically ~1 block (≈ 2 seconds) under normal conditions; if the source chain reorgs past its configured block-safety window (defaulting to 1 block), both chains revert together; eventual finality is via L1.[^SIM_Estimate_Costs][^SIM_Reorg_Awareness]
* **Fallback to L1 ↔ L2 Canonical Bedrock CXM:** If messages involve L1 (e.g., L1 to L2, or L2 to L1), the canonical Bedrock CXM is used. Dispatching an L1→L2 message via `L1CrossDomainMessenger.sendMessage` consumes ≈ 41–43k gas on L1 before calldata. The L2 execution might cost ~25k gas. L2→L1 messages incur a ~7 day delay.
* **Direct On-Chain Oracle:** Using a direct oracle (like Chainlink on an L2) might cost ~50k gas per update on that L2.
* **Optimistic vs ZK Rollup:** On a ZK rollup (if a similar mechanism were used), there's no 7-day delay
  but proving might add cost. However, ERC-76xx as a standard doesn't mandate the rollup type. If used on
  StarkNet, for instance, the data could be passed via L1 and proved in a ZK proof, but analyzing that
  gas cost is complex and beyond this scope. The key point is ERC-76xx doesn't intrinsically add heavy
  cost – it rides on existing messaging infra.
* **CCIP-Read Gas Savings:** By comparison, EIP-3668 (CCIP-Read) can save significant gas by not storing
  large data on-chain. For small oracle values, the savings are modest, but for something like fetching a
  merkle proof with hundreds of entries, CCIP-Read avoids perhaps hundreds of thousands of gas. ERC-76xx
  doesn't directly compete here, as it focuses on cases where the data does need to end up on-chain in
  the target domain.
* **Multiple Recipients / Broadcasts:** If one data update is relevant to several chains (say, an L1
  contract wants to push a value to Optimism, Arbitrum, and Polygon POS), the provider might have to send
  three separate messages (one per chain's messenger). There isn't a native multi-cast in current bridges.
  However, because the data payload is the same, the cost scales linearly with number of chains. This is a
  trade-off to consider. A future optimization could be layer-1 batching: e.g., one L1 transaction that
  emits events for multiple networks' executors, which different relayers then pick up. The ERC-76xx spec
  could allow bundling multiple target chain updates in one call for efficiency (this would be an advanced
  feature beyond MVP).

### Future Integration with Attestation Mechanisms (EAS/Attestation Bus)

The Optimism ecosystem is actively developing standardized attestation infrastructure, including the Ethereum Attestation Service (EAS) and a potential Superchain Attestation Bus. ERC-76xx is designed to be compatible with such advancements.

*   **EAS Compatibility:** An ERC-76xx data update, especially its core payload (e.g., `dataID`, `value`, `timestamp`, `sourceChainID`), can be structured as an EAS attestation. The schema for such attestations could be standardized as part of an ERC-76xx profile. This would allow ERC-76xx data to be recorded and verified using the common EAS framework, enhancing interoperability and discoverability within the Superchain.
*   **Attestation Bus Serialization:** Should a Superchain Attestation Bus be implemented for broadcasting attestations, ERC-76xx messages (formatted as EAS attestations) could be readily serialized for transport via this bus. This would align ERC-76xx with the Superchain's goal of standardized, trust-minimized data propagation, potentially offering an alternative or complementary transport to the direct CXM for certain use cases.

By leveraging EAS and the Attestation Bus, ERC-76xx could further enhance its utility as a standard for cross-chain oracle data, benefiting from shared infrastructure for attestation creation, verification, and transport across the Superchain.

### Benchmark Scenario

As a concrete scenario, consider updating a price feed every 5 minutes from one OP-Stack chain (e.g., Optimism Mainnet) to another (e.g., Unichain) using the Superchain Interop Messenger:
There are 12 updates per hour, 288 per day. Each update costs ~27,100 gas on the source L2 and ~22,100 gas on the destination L2. Total L2 gas per update is ~49,200.
Daily L2 gas: 288 * 49,200 = ~14.17 million gas. L2 gas is significantly cheaper than L1 gas. For example, if L2 gas is $0.000025/gas (a hypothetical value, actual costs vary), this translates to about $0.35/day. This is highly acceptable for critical cross-chain price feeds. Latency would be ~2 seconds per update.

If a feed needed to be sent from L1 to an L2, it would use the canonical Bedrock messenger. At ~45k gas L1 each (dispatch cost, as per earlier estimates which are now primarily for L1-involved paths), that's ~12.96 million gas/day on L1. With ETH at $1800, and an L1 basefee of 10 gwei, this translates to about $233/day. However, L1 basefees vary; for example, if the basefee ranges from 6-15 gwei, the daily L1 cost could range from approximately $140 to $350. The L2 execution cost would add a small amount to this.

Future extensions (e.g., an "ERC-76xx-OPT" profile not using canonical SIM or Bedrock) might define alternative transport mechanisms. In such a hypothetical scenario, L1 might not be hit at all for each update
(the signer could post directly on L2, costing maybe 50k gas on L2 per update, which is a few cents).
But then an occasional reconciliation or proof might be posted on L1 (like once a day or only when
challenged). This hybrid approach could drastically cut costs for those specific, opt-in use cases, at the expense of introducing different trust assumptions and security considerations that would need to be clearly defined and approved within that extension's specification.
ERC-76xx v1.0 for OP-Stack chains, however, commits to SIM for L2-L2 communication and the canonical Bedrock path for L1-involved communication for maximum security.

The above calculations illustrate that ERC-76xx's approach, when using SIM for L2-L2 updates, is economically feasible for high-value,
time-sensitive data. When L1 interaction is needed, the costs are higher but may still be acceptable. It's important that the standard remains lean so that implementers are not deterred by
excessive gas overhead.

[^1]: The EIP-2362 specification *recommends* (SHOULD) a convention for `bytes32` feed IDs (typically derived from `keccak256(symbol, granularity)`), promoting interoperability. However, it does not mandate a single global registry or enforce this scheme, so adherence is de-facto.

## Citations

* [GitHub - tellor-io/EIP-2362: Pull Oracle Interface](https://github.com/tellor-io/EIP-2362)
* [ERC-5164: Cross-Chain Execution](https://eips.ethereum.org/EIPS/eip-5164)
* [EIP-7726: Common Quote Oracle](https://eips.ethereum.org/EIPS/eip-7726)
* [ERC-3668: CCIP Read—Secure offchain data retrieval](https://eips.ethereum.org/EIPS/eip-3668)
* [CCIP-Read - ENS DAO Basics](https://basics.ensdao.org/ccip-read)
* [Discussion EIP-3668: Use of CCIP read for transactions (CCIP write) - EIPs - Fellowship of Ethereum Magicians](https://ethereum-magicians.org/t/discussion-eip-3668-use-of-ccip-read-for-transactions-ccip-write/10977)
* [EIP-5164: Cross-Chain Execution | QX Interoperability - v.0.7](https://qualitax.gitbook.io/interop/industry-initiatives/eip-5164-cross-chain-execution)
* [ERC-7092: Financial Bonds](https://eips.ethereum.org/EIPS/eip-7092)
* [Messengers - OP Stack Specification](https://specs.optimism.io/protocol/messengers.html)
* [Sending data between L1 and L2 | Optimism Docs](https://docs.optimism.io/app-developers/bridging/messaging)
* [Ethereum Evolved: Dencun Upgrade Part 3, EIP-4788 | Consensys](https://consensys.io/blog/ethereum-evolved-dencun-upgrade-part-3-eip-4788)
* [New ERC: Cross-chain broadcaster - ERCs - Fellowship of Ethereum Magicians](https://ethereum-magicians.org/t/new-erc-cross-chain-broadcaster/22927)
* [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
* [Superchain Interop Explainer](docs.optimism.io/stack/interop/explainer)
* [Message Passing](docs.optimism.io/interop/message-passing)
* [Reorg Awareness](docs.optimism.io/interop/reorg-awareness)
* [Estimate Costs - OP Stack Interop](docs.optimism.io/interop/estimate-costs)
* [Compatible Tokens & 1-Block Transfers](docs.optimism.io/interop/compatible-tokens)

```mermaid
graph TD
    subgraph L2SourceOptimism["L2 Source Chain - Optimism"]
        direction LR
        AppSrc["ERC-76xx App/Adapter"]
        SIM_L2ToL2Messenger["L2ToL2CrossDomainMessenger"]
        AppSrc -->|"sendMessage()"| SIM_L2ToL2Messenger
    end

    subgraph RelayerSupervisor["OP Supervisor Network"]
        direction TB
        Relayer["Supervisor/Relayer"]
    end
    SIM_L2ToL2Messenger -->|"SentMessage event"| Relayer

    subgraph L2DestUnichain["L2 Destination Chain - Unichain"]
        direction LR
        SIM_CrossL2Inbox["CrossL2Inbox"]
        ERC76xxProviderDest["ERC-76xx Provider"]
        
        SIM_CrossL2Inbox -->|"receiveUpdate()"| ERC76xxProviderDest
    end
    Relayer -->|"Submit"| SIM_CrossL2Inbox

    classDef simStyle fill:#E6F7FF,stroke:#0066CC,color:#003366
    class SIM_L2ToL2Messenger,SIM_CrossL2Inbox,Relayer simStyle

    subgraph UserAppDest["User Application"]
        AppDestUser["L2 User/App"] -->|"Query"| ERC76xxProviderDest
    end
```
