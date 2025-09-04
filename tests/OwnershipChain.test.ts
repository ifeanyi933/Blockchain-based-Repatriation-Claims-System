import { describe, it, expect, beforeEach } from "vitest";
import { Cl, ClarityValue } from "@stacks/transactions";
import { OwnershipChainMock } from "../mocks/OwnershipChainMock";

// Use valid STX devnet principals
const accounts = {
  deployer: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
  initialOwner: "ST2J9EVYHPYFPJW8P9J7RZ7Y9T8E2ZZ0Q8E9Q6K8M",
  newOwner: "ST3AM1A2B3C4D5E6F7G8H9J0KLMNOPQRSTUVWXYYZ",
  verifier: "ST1J2EVYHPYFPJW8P9J7RZ7Y9T8E2ZZ0Q8E9Q6AAA",
  unauthorized: "ST4BCDEFGHIJKLMNOPQRSUVWTYZ0123456789",
};

describe("OwnershipChain Contract", () => {
  let contract: OwnershipChainMock;

  beforeEach(() => {
    contract = new OwnershipChainMock();
  });

  it("should initialize a new chain successfully", async () => {
    const artifactId = "artifact-001";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    const result = await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial discovery"
    );
    expect(result).toEqual(Cl.ok(Cl.bool(true)));

    const chain = await contract.getOwnershipChain(artifactId);
    expect(chain).toBeDefined();
    expect(chain?.length).toBe(1);
  });

  it("should prevent duplicate chain initialization", async () => {
    const artifactId = "artifact-002";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    expect(result).toEqual(Cl.error(Cl.uint(1)));
  });

  it("should prevent initialization with invalid artifact ID", async () => {
    const result = await contract.initializeChain(
      accounts.initialOwner,
      "",
      accounts.initialOwner,
      Buffer.from("evidencehash1234567890123456789012"),
      "Initial"
    );
    expect(result).toEqual(Cl.error(Cl.uint(3)));
  });

  it("should add a transfer successfully", async () => {
    const artifactId = "artifact-003";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.addTransfer(
      accounts.initialOwner,
      artifactId,
      accounts.newOwner,
      "Sale",
      evidenceHash
    );
    expect(result).toEqual(Cl.ok(Cl.uint(1)));

    const currentOwner = await contract.getCurrentOwner(artifactId);
    expect(currentOwner).toBe(accounts.newOwner);
  });

  it("should prevent transfer by non-owner", async () => {
    const artifactId = "artifact-004";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.addTransfer(
      accounts.unauthorized,
      artifactId,
      accounts.newOwner,
      "Sale",
      evidenceHash
    );
    expect(result).toEqual(Cl.error(Cl.uint(2)));
  });

  it("should propose an amendment successfully", async () => {
    const artifactId = "artifact-005";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.proposeAmendment(
      accounts.initialOwner,
      artifactId,
      0,
      null,
      accounts.newOwner,
      null,
      null
    );
    expect(result).toEqual(Cl.ok(Cl.uint(0)));
  });

  it("should approve and apply amendment", async () => {
    const artifactId = "artifact-006";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    await contract.addVerifier(accounts.initialOwner, artifactId, accounts.verifier, ["approve-amendment"]);
    await contract.proposeAmendment(
      accounts.initialOwner,
      artifactId,
      0,
      null,
      accounts.newOwner,
      null,
      null
    );
    const approveResult = await contract.approveAmendment(accounts.verifier, artifactId, 0);
    expect(approveResult).toEqual(Cl.ok(Cl.bool(true)));

    const currentOwner = await contract.getCurrentOwner(artifactId);
    expect(currentOwner).toBe(accounts.newOwner);
  });

  it("should validate chain integrity", async () => {
    const artifactId = "artifact-007";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    await contract.addTransfer(
      accounts.initialOwner,
      artifactId,
      accounts.newOwner,
      "Sale",
      evidenceHash
    );
    const result = await contract.validateChainIntegrity(artifactId);
    expect(result).toEqual(Cl.ok(Cl.bool(true)));
  });

  it("should get owner at block", async () => {
    const artifactId = "artifact-008";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.getOwnerAtBlock(artifactId, 1);
    expect(result).toBe(accounts.initialOwner);
  });

  it("should add verifier successfully", async () => {
    const artifactId = "artifact-009";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    const result = await contract.addVerifier(
      accounts.initialOwner,
      artifactId,
      accounts.verifier,
      ["approve-amendment"]
    );
    expect(result).toEqual(Cl.ok(Cl.bool(true)));

    const hasPerm = await contract.hasPermission(artifactId, accounts.verifier, "approve-amendment");
    expect(hasPerm).toEqual(Cl.ok(Cl.bool(true)));
  });

  it("should lock chain successfully", async () => {
    const artifactId = "artifact-010";
    const evidenceHash = Buffer.from("evidencehash1234567890123456789012");
    await contract.initializeChain(
      accounts.initialOwner,
      artifactId,
      accounts.initialOwner,
      evidenceHash,
      "Initial"
    );
    await contract.addVerifier(accounts.initialOwner, artifactId, accounts.verifier, ["lock-chain"]);
    const result = await contract.lockChain(accounts.verifier, artifactId, true);
    expect(result).toEqual(Cl.ok(Cl.bool(true)));
  });
});