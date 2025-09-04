import { Cl, ClarityValue, cvToValue } from "@stacks/transactions";

type Transfer = {
  prevOwner: string;
  newOwner: string;
  timestamp: number;
  reason: string;
  evidenceHash: Buffer;
  transferId: number;
};

type Amendment = {
  targetTransferId: number;
  proposedChanges: {
    newPrevOwner?: string;
    newNewOwner?: string;
    newReason?: string;
    newEvidenceHash?: Buffer;
  };
  proposer: string;
  approvals: string[];
  status: string;
  timestamp: number;
};

type Verifier = {
  addedBy: string;
  addedAt: number;
  permissions: string[];
};

export class OwnershipChainMock {
  private chains: Map<string, Transfer[]> = new Map();
  private metadata: Map<string, { initialOwner: string; creationTimestamp: number; lastTransferId: number; isLocked: boolean; amendmentCount: number }> = new Map();
  private amendments: Map<string, Amendment[]> = new Map();
  private verifiers: Map<string, Map<string, Verifier>> = new Map();
  private currentBlock: number = 1;

  private isError(value: ClarityValue): boolean {
    return (cvToValue(value) as any).type === Cl.error(undefined).type;
  }

  async initializeChain(_sender: string, artifactId: string, initialOwner: string, evidenceHash: Buffer, initialReason: string): Promise<ClarityValue> {
    if (!artifactId) return Cl.error(Cl.uint(3));
    if (this.chains.has(artifactId)) return Cl.error(Cl.uint(1));

    this.chains.set(artifactId, [{
      prevOwner: initialOwner,
      newOwner: initialOwner,
      timestamp: this.currentBlock,
      reason: initialReason,
      evidenceHash,
      transferId: 0
    }]);
    this.metadata.set(artifactId, {
      initialOwner,
      creationTimestamp: this.currentBlock,
      lastTransferId: 0,
      isLocked: false,
      amendmentCount: 0
    });
    this.amendments.set(artifactId, []);
    this.verifiers.set(artifactId, new Map());
    this.currentBlock++;
    return Cl.ok(Cl.bool(true));
  }

  async getOwnershipChain(artifactId: string): Promise<Transfer[] | undefined> {
    return this.chains.get(artifactId);
  }

  async getChainMetadata(artifactId: string): Promise<ClarityValue | undefined> {
    const meta = this.metadata.get(artifactId);
    if (!meta) return undefined;
    return Cl.tuple({
      "initial-owner": Cl.principal(meta.initialOwner),
      "creation-timestamp": Cl.uint(meta.creationTimestamp),
      "last-transfer-id": Cl.uint(meta.lastTransferId),
      "is-locked": Cl.bool(meta.isLocked),
      "amendment-count": Cl.uint(meta.amendmentCount)
    });
  }

  async addTransfer(sender: string, artifactId: string, newOwner: string, reason: string, evidenceHash: Buffer): Promise<ClarityValue> {
    const chain = this.chains.get(artifactId);
    if (!chain) return Cl.error(Cl.uint(5));
    const meta = this.metadata.get(artifactId)!;
    const currentOwner = chain[chain.length - 1].newOwner;
    if (currentOwner !== sender) return Cl.error(Cl.uint(2));
    if (meta.isLocked) return Cl.error(Cl.uint(10));
    if (chain.length >= 200) return Cl.error(Cl.uint(7));

    const newTransferId = meta.lastTransferId + 1;
    chain.push({
      prevOwner: currentOwner,
      newOwner,
      timestamp: this.currentBlock,
      reason,
      evidenceHash,
      transferId: newTransferId
    });
    meta.lastTransferId = newTransferId;
    this.currentBlock++;
    return Cl.ok(Cl.uint(newTransferId));
  }

  async proposeAmendment(sender: string, artifactId: string, targetTransferId: number, newPrevOwner: string | null, newNewOwner: string | null, newReason: string | null, newEvidenceHash: Buffer | null): Promise<ClarityValue> {
    const meta = this.metadata.get(artifactId);
    if (!meta) return Cl.error(Cl.uint(5));
    const isAuthorized = await this.isAuthorizedFor(artifactId, sender, "propose-amendment");
    if (this.isError(isAuthorized)) return isAuthorized;
    if (meta.amendmentCount >= 50) return Cl.error(Cl.uint(12));

    const changes: Amendment["proposedChanges"] = {};
    if (newPrevOwner) changes.newPrevOwner = newPrevOwner;
    if (newNewOwner) changes.newNewOwner = newNewOwner;
    if (newReason) changes.newReason = newReason;
    if (newEvidenceHash) changes.newEvidenceHash = newEvidenceHash;

    if (Object.keys(changes).length === 0) return Cl.error(Cl.uint(11));

    const newAmendmentId = meta.amendmentCount;
    this.amendments.get(artifactId)!.push({
      targetTransferId,
      proposedChanges: changes,
      proposer: sender,
      approvals: [sender],
      status: "pending",
      timestamp: this.currentBlock
    });
    meta.amendmentCount++;
    meta.isLocked = true;
    this.currentBlock++;
    return Cl.ok(Cl.uint(newAmendmentId));
  }

  async approveAmendment(sender: string, artifactId: string, amendmentId: number): Promise<ClarityValue> {
    const amendments = this.amendments.get(artifactId);
    if (!amendments || !amendments[amendmentId]) return Cl.error(Cl.uint(5));
    const amendment = amendments[amendmentId];
    const isAuthorized = await this.isAuthorizedFor(artifactId, sender, "approve-amendment");
    if (this.isError(isAuthorized)) return isAuthorized;
    if (amendment.status !== "pending") return Cl.error(Cl.uint(11));
    if (amendment.approvals.includes(sender)) return Cl.error(Cl.uint(1));

    amendment.approvals.push(sender);
    if (amendment.approvals.length >= 2) {
      amendment.status = "approved";
      const chain = this.chains.get(artifactId)!;
      const targetEntry = chain.find(e => e.transferId === amendment.targetTransferId);
      if (!targetEntry) return Cl.error(Cl.uint(5));
      if (amendment.proposedChanges.newPrevOwner) targetEntry.prevOwner = amendment.proposedChanges.newPrevOwner;
      if (amendment.proposedChanges.newNewOwner) targetEntry.newOwner = amendment.proposedChanges.newNewOwner;
      if (amendment.proposedChanges.newReason) targetEntry.reason = amendment.proposedChanges.newReason;
      if (amendment.proposedChanges.newEvidenceHash) targetEntry.evidenceHash = amendment.proposedChanges.newEvidenceHash;
      this.metadata.get(artifactId)!.isLocked = false;
      return Cl.ok(Cl.bool(true));
    }
    return Cl.ok(Cl.bool(false));
  }

  async addVerifier(sender: string, artifactId: string, verifier: string, permissions: string[]): Promise<ClarityValue> {
    const currentOwner = this.getCurrentOwner(artifactId);
    if (!currentOwner) return Cl.error(Cl.uint(5));
    if (currentOwner !== sender) return Cl.error(Cl.uint(2));
    const verifiers = this.verifiers.get(artifactId)!;
    if (verifiers.has(verifier)) return Cl.error(Cl.uint(1));

    verifiers.set(verifier, { addedBy: sender, addedAt: this.currentBlock, permissions });
    return Cl.ok(Cl.bool(true));
  }

  async lockChain(sender: string, artifactId: string, lock: boolean): Promise<ClarityValue> {
    const isAuthorized = await this.isAuthorizedFor(artifactId, sender, "lock-chain");
    if (this.isError(isAuthorized)) return isAuthorized;
    const meta = this.metadata.get(artifactId);
    if (!meta) return Cl.error(Cl.uint(5));
    meta.isLocked = lock;
    return Cl.ok(Cl.bool(true));
  }

  getCurrentOwner(artifactId: string): string | undefined {
    const chain = this.chains.get(artifactId);
    if (!chain) return undefined;
    return chain[chain.length - 1].newOwner;
  }

  async getOwnerAtBlock(artifactId: string, targetBlock: number): Promise<string | undefined> {
    const chain = this.chains.get(artifactId);
    if (!chain) return undefined;
    let owner: string | undefined;
    for (const entry of chain) {
      if (entry.timestamp <= targetBlock) {
        owner = entry.newOwner;
      } else {
        break;
      }
    }
    return owner;
  }

  async validateChainIntegrity(artifactId: string): Promise<ClarityValue> {
    const chain = this.chains.get(artifactId);
    if (!chain) return Cl.error(Cl.uint(5));
    for (let i = 1; i < chain.length; i++) {
      if (chain[i].prevOwner !== chain[i - 1].newOwner) {
        return Cl.error(Cl.uint(6));
      }
    }
    return Cl.ok(Cl.bool(true));
  }

  async hasPermission(artifactId: string, verifier: string, permission: string): Promise<ClarityValue> {
    const verifiers = this.verifiers.get(artifactId);
    if (!verifiers) return Cl.error(Cl.uint(8));
    const info = verifiers.get(verifier);
    if (!info) return Cl.error(Cl.uint(8));
    return Cl.ok(Cl.bool(info.permissions.includes(permission)));
  }

  private async isAuthorizedFor(artifactId: string, caller: string, permission: string): Promise<ClarityValue> {
    const currentOwner = this.getCurrentOwner(artifactId);
    if (!currentOwner) return Cl.error(Cl.uint(5));
    if (caller === currentOwner) return Cl.ok(Cl.bool(true));
    return this.hasPermission(artifactId, caller, permission);
  }
}