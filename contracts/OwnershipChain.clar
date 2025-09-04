;; OwnershipChain Smart Contract
;; This contract manages immutable ownership chains for cultural artifacts in a repatriation claims system.
;; It tracks historical transfers, validates chain integrity, and provides verification tools for claims.
;; Features include transfer logging with evidence, chain validation, owner history queries,
;; amendment handling for corrections (with multi-approval), and integration hooks for claims.
;; Designed to be robust, with bounded data structures, error handling, and read-only audits.

;; Constants
(define-constant ERR-ALREADY-INITIALIZED u1)
(define-constant ERR-NOT-OWNER u2)
(define-constant ERR-INVALID-ARTIFACT-ID u3)
(define-constant ERR-INVALID-PARAM u4)
(define-constant ERR-NOT-FOUND u5)
(define-constant ERR-CHAIN-BROKEN u6)
(define-constant ERR-MAX-TRANSFERS-REACHED u7)
(define-constant ERR-NOT-AUTHORIZED u8)
(define-constant ERR-INVALID-EVIDENCE-HASH u9)
(define-constant ERR-AMENDMENT-PENDING u10)
(define-constant ERR-INVALID-AMENDMENT u11)
(define-constant ERR-MAX-AMENDMENTS-REACHED u12)
(define-constant ERR-INVALID-BLOCK-HEIGHT u13)
(define-constant MAX-TRANSFERS 200) ;; Max history depth to prevent unbounded growth
(define-constant MAX-AMENDMENTS 50) ;; Max amendments per chain
(define-constant MIN_TRANSFER_REASON_LEN u10) ;; Ensure meaningful reasons
(define-constant AMENDMENT_APPROVAL_THRESHOLD u2) ;; Min approvals for amendment (e.g., owner + verifier)

;; Data Maps
(define-map ownership-chains
  { artifact-id: (string-ascii 64) } ;; Unique artifact identifier
  (list 200 ;; Bounded list of transfers
    {
      prev-owner: principal,
      new-owner: principal,
      timestamp: uint, ;; Block height
      reason: (string-utf8 256), ;; e.g., "sale", "donation", "repatriation"
      evidence-hash: (buff 32), ;; SHA-256 of supporting docs
      transfer-id: uint ;; Sequential ID
    }
  )
)

(define-map chain-metadata
  { artifact-id: (string-ascii 64) }
  {
    initial-owner: principal,
    creation-timestamp: uint,
    last-transfer-id: uint,
    is-locked: bool, ;; Lock during active claims
    amendment-count: uint
  }
)

(define-map amendments
  { artifact-id: (string-ascii 64), amendment-id: uint }
  {
    target-transfer-id: uint, ;; Which transfer to amend
    proposed-changes: {
      new-prev-owner: (optional principal),
      new-new-owner: (optional principal),
      new-reason: (optional (string-utf8 256)),
      new-evidence-hash: (optional (buff 32))
    },
    proposer: principal,
    approvals: (list 5 principal), ;; Approvers (bounded)
    status: (string-ascii 20), ;; "pending", "approved", "rejected"
    timestamp: uint
  }
)

(define-map authorized-verifiers
  { artifact-id: (string-ascii 64), verifier: principal }
  {
    added-by: principal,
    added-at: uint,
    permissions: (list 3 (string-ascii 50)) ;; e.g., "approve-amendment", "lock-chain"
  }
)

;; Public Functions

(define-public (initialize-chain 
  (artifact-id (string-ascii 64))
  (initial-owner principal)
  (initial-evidence-hash (buff 32))
  (initial-reason (string-utf8 256)))
  (let
    ((existing-chain (map-get? ownership-chains {artifact-id: artifact-id}))
     (valid-id (validate-artifact-id artifact-id))
     (valid-hash (validate-evidence-hash initial-evidence-hash))
     (valid-reason (validate-reason initial-reason)))
    (try! valid-id)
    (try! valid-hash)
    (try! valid-reason)
    (if (is-some existing-chain)
      (err ERR-ALREADY-INITIALIZED)
      (begin
        (map-set ownership-chains
          {artifact-id: artifact-id}
          (list 
            {
              prev-owner: initial-owner, ;; Initial: prev = new for genesis
              new-owner: initial-owner,
              timestamp: block-height,
              reason: initial-reason,
              evidence-hash: initial-evidence-hash,
              transfer-id: u0
            }
          )
        )
        (map-set chain-metadata
          {artifact-id: artifact-id}
          {
            initial-owner: initial-owner,
            creation-timestamp: block-height,
            last-transfer-id: u0,
            is-locked: false,
            amendment-count: u0
          }
        )
        (print { event: "chain-initialized", artifact-id: artifact-id, owner: initial-owner })
        (ok true)
      )
    )
  )
)

(define-public (add-transfer 
  (artifact-id (string-ascii 64))
  (new-owner principal)
  (reason (string-utf8 256))
  (evidence-hash (buff 32)))
  (let
    ((chain (unwrap! (map-get? ownership-chains {artifact-id: artifact-id}) (err ERR-NOT-FOUND)))
     (metadata (unwrap! (map-get? chain-metadata {artifact-id: artifact-id}) (err ERR-NOT-FOUND)))
     (current-owner (get new-owner (unwrap-panic (element-at? chain (- (len chain) u1)))))
     (valid-reason (validate-reason reason))
     (valid-hash (validate-evidence-hash evidence-hash)))
    (try! valid-reason)
    (try! valid-hash)
    (if (not (is-eq current-owner tx-sender))
      (err ERR-NOT-OWNER)
      (if (get is-locked metadata)
        (err ERR-AMENDMENT-PENDING)
        (if (>= (len chain) MAX-TRANSFERS)
          (err ERR-MAX-TRANSFERS-REACHED)
          (let
            ((new-transfer-id (+ (get last-transfer-id metadata) u1))
             (new-entry {
               prev-owner: current-owner,
               new-owner: new-owner,
               timestamp: block-height,
               reason: reason,
               evidence-hash: evidence-hash,
               transfer-id: new-transfer-id
             }))
            (map-set ownership-chains
              {artifact-id: artifact-id}
              (unwrap-panic (as-max-len? (append chain new-entry) u200))
            )
            (map-set chain-metadata
              {artifact-id: artifact-id}
              (merge metadata { last-transfer-id: new-transfer-id })
            )
            (print { event: "transfer-added", artifact-id: artifact-id, from: current-owner, to: new-owner })
            (ok new-transfer-id)
          )
        )
      )
    )
  )
)

(define-public (propose-amendment 
  (artifact-id (string-ascii 64))
  (target-transfer-id uint)
  (new-prev-owner (optional principal))
  (new-new-owner (optional principal))
  (new-reason (optional (string-utf8 256)))
  (new-evidence-hash (optional (buff 32))))
  (let
    ((metadata (unwrap! (map-get? chain-metadata {artifact-id: artifact-id}) (err ERR-NOT-FOUND)))
     (is-authorized (is-authorized-for artifact-id tx-sender "propose-amendment")))
    (try! is-authorized)
    (if (>= (get amendment-count metadata) MAX-AMENDMENTS)
      (err ERR-MAX-AMENDMENTS-REACHED)
      (let
        ((new-amendment-id (get amendment-count metadata))
         (changes { new-prev-owner: new-prev-owner, new-new-owner: new-new-owner, new-reason: new-reason, new-evidence-hash: new-evidence-hash }))
        (if (or (is-none new-prev-owner) (is-none new-new-owner) (is-none new-reason) (is-none new-evidence-hash))
          (if (and (is-none new-prev-owner) (is-none new-new-owner) (is-none new-reason) (is-none new-evidence-hash))
            (err ERR-INVALID-AMENDMENT)
            (begin
              (map-set amendments
                {artifact-id: artifact-id, amendment-id: new-amendment-id}
                {
                  target-transfer-id: target-transfer-id,
                  proposed-changes: changes,
                  proposer: tx-sender,
                  approvals: (list tx-sender),
                  status: "pending",
                  timestamp: block-height
                }
              )
              (map-set chain-metadata
                {artifact-id: artifact-id}
                (merge metadata { amendment-count: (+ new-amendment-id u1), is-locked: true })
              )
              (print { event: "amendment-proposed", artifact-id: artifact-id, id: new-amendment-id })
              (ok new-amendment-id)
            )
          )
          (err ERR-INVALID-AMENDMENT)
        )
      )
    )
  )
)

(define-public (approve-amendment 
  (artifact-id (string-ascii 64))
  (amendment-id uint))
  (let
    ((amendment (unwrap! (map-get? amendments {artifact-id: artifact-id, amendment-id: amendment-id}) (err ERR-NOT-FOUND)))
     (is-authorized (is-authorized-for artifact-id tx-sender "approve-amendment")))
    (try! is-authorized)
    (if (not (is-eq (get status amendment) "pending"))
      (err ERR-INVALID-AMENDMENT)
      (let
        ((new-approvals (unwrap-panic (as-max-len? (append (get approvals amendment) tx-sender) u5))))
        (if (is-some (index-of? (get approvals amendment) tx-sender))
          (err ERR-ALREADY-INITIALIZED) ;; Already approved
          (begin
            (map-set amendments
              {artifact-id: artifact-id, amendment-id: amendment-id}
              (merge amendment { approvals: new-approvals })
            )
            (if (>= (len new-approvals) AMENDMENT_APPROVAL_THRESHOLD)
              (try! (apply-amendment artifact-id amendment-id amendment))
              (ok false) ;; Not yet approved
            )
          )
        )
      )
    )
  )
)

(define-public (add-verifier 
  (artifact-id (string-ascii 64))
  (verifier principal)
  (permissions (list 3 (string-ascii 50))))
  (let
    ((metadata (unwrap! (map-get? chain-metadata {artifact-id: artifact-id}) (err ERR-NOT-FOUND)))
     (current-owner (get-current-owner artifact-id)))
    (if (is-eq current-owner tx-sender)
      (if (is-some (map-get? authorized-verifiers {artifact-id: artifact-id, verifier: verifier}))
        (err ERR-ALREADY-INITIALIZED)
        (begin
          (map-set authorized-verifiers
            {artifact-id: artifact-id, verifier: verifier}
            { added-by: tx-sender, added-at: block-height, permissions: permissions }
          )
          (ok true)
        )
      )
      (err ERR-NOT-OWNER)
    )
  )
)

(define-public (lock-chain (artifact-id (string-ascii 64)) (lock bool))
  (let
    ((metadata (unwrap! (map-get? chain-metadata {artifact-id: artifact-id}) (err ERR-NOT-FOUND)))
     (is-authorized (is-authorized-for artifact-id tx-sender "lock-chain")))
    (try! is-authorized)
    (map-set chain-metadata
      {artifact-id: artifact-id}
      (merge metadata { is-locked: lock })
    )
    (print { event: "chain-locked", artifact-id: artifact-id, locked: lock })
    (ok true)
  )
)

;; Read-Only Functions

(define-read-only (get-ownership-chain (artifact-id (string-ascii 64)))
  (map-get? ownership-chains {artifact-id: artifact-id})
)

(define-read-only (get-chain-metadata (artifact-id (string-ascii 64)))
  (map-get? chain-metadata {artifact-id: artifact-id})
)

(define-read-only (get-amendment (artifact-id (string-ascii 64)) (amendment-id uint))
  (map-get? amendments {artifact-id: artifact-id, amendment-id: amendment-id})
)

(define-read-only (get-verifier (artifact-id (string-ascii 64)) (verifier principal))
  (map-get? authorized-verifiers {artifact-id: artifact-id, verifier: verifier})
)

(define-read-only (get-current-owner (artifact-id (string-ascii 64)))
  (let
    ((chain (unwrap! (map-get? ownership-chains {artifact-id: artifact-id}) ERR-NOT-FOUND)))
    (get new-owner (unwrap! (element-at? chain (- (len chain) u1)) ERR-CHAIN-BROKEN))
  )
)

(define-read-only (get-owner-at-block (artifact-id (string-ascii 64)) (target-block uint))
  (let
    ((chain (unwrap! (map-get? ownership-chains {artifact-id: artifact-id}) ERR-NOT-FOUND)))
    (fold find-owner-at-block chain { found: none, target: target-block })
  )
)

(define-read-only (validate-chain-integrity (artifact-id (string-ascii 64)))
  (let
    ((chain (unwrap! (map-get? ownership-chains {artifact-id: artifact-id}) (err ERR-NOT-FOUND))))
    (fold check-chain-link (cdr chain) (ok (car chain)))
  )
)

(define-read-only (has-permission (artifact-id (string-ascii 64)) (verifier principal) (permission (string-ascii 50)))
  (let
    ((verifier-info (map-get? authorized-verifiers {artifact-id: artifact-id, verifier: verifier})))
    (match verifier-info
      some-info
      (ok (is-some (index-of? (get permissions some-info) permission)))
      (err ERR-NOT-AUTHORIZED)
    )
  )
)

;; Private Functions

(define-private (validate-artifact-id (artifact-id (string-ascii 64)))
  (if (or (is-eq (len artifact-id) u0) (> (len artifact-id) u64))
    (err ERR-INVALID-ARTIFACT-ID)
    (ok true)
  )
)

(define-private (validate-evidence-hash (hash (buff 32)))
  (if (is-eq (len hash) u32)
    (ok true)
    (err ERR-INVALID-EVIDENCE-HASH)
  )
)

(define-private (validate-reason (reason (string-utf8 256)))
  (if (or (< (len reason) MIN_TRANSFER_REASON_LEN) (> (len reason) u256))
    (err ERR-INVALID-PARAM)
    (ok true)
  )
)

(define-private (is-authorized-for (artifact-id (string-ascii 64)) (caller principal) (permission (string-ascii 50)))
  (let
    ((current-owner (get-current-owner artifact-id))
     (verifier-perms (has-permission artifact-id caller permission)))
    (if (is-eq caller current-owner)
      (ok true)
      verifier-perms
    )
  )
)

(define-private (apply-amendment (artifact-id (string-ascii 64)) (amendment-id uint) (amendment 
  {
    target-transfer-id: uint,
    proposed-changes: {
      new-prev-owner: (optional principal),
      new-new-owner: (optional principal),
      new-reason: (optional (string-utf8 256)),
      new-evidence-hash: (optional (buff 32))
    },
    proposer: principal,
    approvals: (list 5 principal),
    status: (string-ascii 20),
    timestamp: uint
  }))
  (let
    ((chain (unwrap-panic (map-get? ownership-chains {artifact-id: artifact-id})))
     (metadata (unwrap-panic (map-get? chain-metadata {artifact-id: artifact-id})))
     (target-index (fold find-transfer-index chain { target: (get target-transfer-id amendment), index: u0, found: none })))
    (match target-index
      some-index
      (let
        ((old-entry (unwrap-panic (element-at? chain some-index)))
         (changes (get proposed-changes amendment))
         (new-entry (merge old-entry {
           prev-owner: (default-to (get prev-owner old-entry) (get new-prev-owner changes)),
           new-owner: (default-to (get new-owner old-entry) (get new-new-owner changes)),
           reason: (default-to (get reason old-entry) (get new-reason changes)),
           evidence-hash: (default-to (get evidence-hash old-entry) (get new-evidence-hash changes))
         })))
        (map-set ownership-chains
          {artifact-id: artifact-id}
          (unwrap-panic (replace-at? chain some-index new-entry))
        )
        (map-set amendments
          {artifact-id: artifact-id, amendment-id: amendment-id}
          (merge amendment { status: "approved" })
        )
        (map-set chain-metadata
          {artifact-id: artifact-id}
          (merge metadata { is-locked: false })
        )
        (print { event: "amendment-applied", artifact-id: artifact-id, id: amendment-id })
        (ok true)
      )
      (err ERR_NOT_FOUND)
    )
  )
)

(define-private (find-transfer-index (entry 
  {
    prev-owner: principal,
    new-owner: principal,
    timestamp: uint,
    reason: (string-utf8 256),
    evidence-hash: (buff 32),
    transfer-id: uint
  }) (acc { target: uint, index: uint, found: (optional uint) }))
  (match (get found acc)
    some-found acc
    (if (is-eq (get transfer-id entry) (get target acc))
      (merge acc { found: (some (get index acc)) })
      (merge acc { index: (+ (get index acc) u1) })
    )
  )
)

(define-private (find-owner-at-block (entry 
  {
    prev-owner: principal,
    new-owner: principal,
    timestamp: uint,
    reason: (string-utf8 256),
    evidence-hash: (buff 32),
    transfer-id: uint
  }) (acc { found: (optional principal), target: uint }))
  (if (is-some (get found acc))
    acc
    (if (<= (get timestamp entry) (get target acc))
      (merge acc { found: (some (get new-owner entry)) })
      acc
    )
  )
)

(define-private (check-chain-link (entry 
  {
    prev-owner: principal,
    new-owner: principal,
    timestamp: uint,
    reason: (string-utf8 256),
    evidence-hash: (buff 32),
    transfer-id: uint
  }) (prev-result (response 
  {
    prev-owner: principal,
    new-owner: principal,
    timestamp: uint,
    reason: (string-utf8 256),
    evidence-hash: (buff 32),
    transfer-id: uint
  } uint)))
  (match prev-result
    prev-entry
    (if (is-eq (get new-owner prev-entry) (get prev-owner entry))
      (ok entry)
      (err ERR_CHAIN_BROKEN)
    )
    err err
  )
)