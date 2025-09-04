# 🏛️ Blockchain-based Repatriation Claims System

Welcome to a revolutionary Web3 solution for handling repatriation claims of cultural artifacts! This project addresses the real-world problem of disputed ownership in museums and collections worldwide, where historical artifacts (like ancient relics, artworks, or cultural items) are often claimed by indigenous communities, nations, or rightful heirs due to colonialism, looting, or theft. By leveraging the Stacks blockchain and Clarity smart contracts, we create an immutable, transparent ledger of ownership chains, enabling verifiable provenance tracking, claim submissions, and resolution processes. This reduces reliance on opaque legal systems, minimizes fraud, and promotes ethical repatriation.

## ✨ Features

🔒 Immutable ownership chains to track artifact provenance from discovery to current holder  
📜 Register artifacts with historical metadata and initial ownership proofs  
⚖️ Submit and verify repatriation claims with evidence uploads (hashed for privacy)  
🕵️‍♂️ Automated verification of historical transfers using blockchain timestamps  
🤝 Dispute resolution via multi-party voting or oracle integrations  
📊 Audit trails for all actions, ensuring transparency for stakeholders like museums, governments, and communities  
🚫 Anti-fraud measures to prevent duplicate claims or forged histories  
🌍 Global accessibility for international claims, with support for tokenized artifacts (as NFTs)  

## 🛠 How It Works

This system is built on the Stacks blockchain using Clarity smart contracts. It involves 8 interconnected smart contracts to handle registration, transfers, claims, verification, and resolution. Each contract is designed for modularity, security, and efficiency, with read-only functions for queries and write functions protected by ownership checks.

### Core Smart Contracts

1. **ArtifactRegistry.clar**: Handles initial registration of artifacts. Creators (e.g., museums or finders) submit a unique artifact ID, metadata (description, origin, discovery date), and a hash of supporting documents. Emits an event for the initial ownership chain entry.

2. **OwnershipChain.clar**: Manages the historical ledger of ownership. Each transfer appends to the chain with timestamps, previous owner signatures, and transfer reasons (e.g., sale, donation, repatriation). Uses maps to store chains per artifact ID for efficient lookups.

3. **TransferManager.clar**: Facilitates secure ownership transfers. Requires multi-signature approval from current owner and recipient. Integrates with OwnershipChain to update the ledger atomically, preventing invalid states.

4. **ClaimSubmission.clar**: Allows claimants (e.g., indigenous groups or nations) to file repatriation claims. Submits evidence hashes, claim details, and links to the artifact ID. Locks the artifact's transferability during active claims to avoid disputes.

5. **EvidenceVerifier.clar**: Verifies submitted evidence against the ownership chain. Uses Clarity's built-in hashing and comparison functions to check for inconsistencies in historical data. Can integrate with external oracles for off-chain validation (e.g., carbon dating reports).

6. **DisputeResolution.clar**: Implements a voting mechanism for resolving claims. Stakeholders (pre-registered via UserRegistry) vote on claim validity within a time window. Uses weighted voting based on roles (e.g., experts, governments) and resolves via majority or supermajority.

7. **UserRegistry.clar**: Registers and authenticates users/entities (museums, claimants, experts). Stores roles, public keys, and verification status to ensure only authorized parties interact with the system.

8. **AuditLog.clar**: Logs all system events immutably (registrations, transfers, claims, resolutions). Provides query functions for public audits, enhancing trust and compliance with international laws like UNESCO conventions.

### For Artifact Holders (e.g., Museums)

- Register your artifact via ArtifactRegistry with metadata and proof hash.  
- Use TransferManager to record any ownership changes, building the chain in OwnershipChain.  
- If a claim arises, respond via DisputeResolution with counter-evidence.

Boom! Your artifact's history is now transparently secured on the blockchain.

### For Claimants (e.g., Communities or Nations)

- Search for an artifact using read-only functions in OwnershipChain.  
- Submit a claim through ClaimSubmission, including hashed evidence of prior ownership or theft.  
- Participate in voting via DisputeResolution to advocate for repatriation.

### For Verifiers (e.g., Experts or Regulators)

- Query OwnershipChain and AuditLog to trace the full history.  
- Use EvidenceVerifier to confirm claim validity instantly.  
- Vote in DisputeResolution if registered as a stakeholder.

That's it! This system empowers fair, data-driven repatriation, reducing costly legal battles and fostering cultural justice worldwide.