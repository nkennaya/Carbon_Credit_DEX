;; Carbon Credit DEX - Environmental Asset Exchange
;; Addressing ESG trends and $10.2B AI-crypto revenue projection by 2030
;; Decentralized exchange for tokenized carbon credits with AI verification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-invalid-credit (err u1300))
(define-constant err-insufficient-credits (err u1301))
(define-constant err-verification-failed (err u1302))
(define-constant err-already-verified (err u1303))
(define-constant err-expired-credit (err u1304))
(define-constant err-invalid-project (err u1305))
(define-constant err-duplicate-serial (err u1306))
(define-constant err-not-verifier (err u1307))

;; Carbon credit parameters
(define-constant min-credit-amount u1000) ;; 1 tonne CO2 minimum
(define-constant verification-fee u5000000) ;; 5 STX
(define-constant retirement-bonus u100000) ;; 0.1 STX per tonne retired
(define-constant max-credit-age u52560) ;; ~1 year in blocks

;; Data Variables
(define-data-var total-credits-issued uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var total-trading-volume uint u0)
(define-data-var carbon-price-index uint u50000000) ;; $50 per tonne in microSTX

;; NFT for carbon credit batches
(define-non-fungible-token carbon-credit-batch uint)

;; Fungible token for fractional credits
(define-fungible-token carbon-token)

;; Maps
(define-map carbon-projects
    uint ;; project-id
    {
        name: (string-ascii 100),
        location: (string-ascii 50),
        project-type: (string-ascii 30), ;; "renewable", "reforestation", "capture"
        vintage-year: uint,
        total-credits: uint,
        verified-credits: uint,
        retired-credits: uint,
        verifier: principal,
        methodology: (string-ascii 50),
        is-active: bool
    }
)

(define-map credit-batches
    uint ;; batch-id
    {
        project-id: uint,
        serial-number: (string-ascii 50),
        tonnage: uint,
        issuance-date: uint,
        expiry-date: uint,
        owner: principal,
        is-retired: bool,
        retirement-beneficiary: (optional principal),
        verification-hash: (buff 32),
        ai-confidence-score: uint
    }
)

(define-map market-orders
    uint ;; order-id
    {
        seller: principal,
        batch-id: uint,
        tonnage-available: uint,
        price-per-tonne: uint,
        min-purchase: uint,
        order-type: (string-ascii 10), ;; "spot" or "forward"
        expiry-block: uint,
        filled: uint
    }
)

(define-map retirement-certificates
    uint ;; certificate-id
    {
        retiree: principal,
        batch-id: uint,
        tonnage: uint,
        retirement-date: uint,
        beneficiary: (string-ascii 100),
        purpose: (string-utf8 200),
        certificate-hash: (buff 32)
    }
)

(define-map verified-entities
    principal
    {
        entity-type: (string-ascii 20), ;; "verifier", "project", "auditor"
        reputation-score: uint,
        total-verified: uint,
        disputes: uint,
        stake-amount: uint
    }
)

;; Helper functions
(define-private (min (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (max (a uint) (b uint))
    (if (> a b) a b)
)

;; Read-only functions
(define-read-only (get-project (project-id uint))
    (map-get? carbon-projects project-id)
)

(define-read-only (get-batch (batch-id uint))
    (map-get? credit-batches batch-id)
)

(define-read-only (get-carbon-price)
    (var-get carbon-price-index)
)

(define-read-only (calculate-environmental-impact (tonnage uint))
    {
        co2-reduced: tonnage,
        trees-equivalent: (* tonnage u15), ;; ~15 trees per tonne CO2
        cars-off-road: (/ tonnage u4), ;; ~4 tonnes per car annually
        homes-powered: (/ tonnage u11) ;; ~11 tonnes per home annually
    }
)

;; Public functions

;; Register carbon project
(define-public (register-project
    (name (string-ascii 100))
    (location (string-ascii 50))
    (project-type (string-ascii 30))
    (vintage-year uint)
    (estimated-credits uint)
    (methodology (string-ascii 50)))
    (let (
        (project-id (+ (var-get total-credits-issued) u1000)) ;; Offset to distinguish from batches
    )
        ;; Check if caller is verified entity
        (let (
            (entity (map-get? verified-entities tx-sender))
        )
            (asserts! (and (is-some entity) 
                          (is-eq (get entity-type (unwrap-panic entity)) "project")) 
                     err-not-verifier)
        )
        
        (map-set carbon-projects project-id {
            name: name,
            location: location,
            project-type: project-type,
            vintage-year: vintage-year,
            total-credits: estimated-credits,
            verified-credits: u0,
            retired-credits: u0,
            verifier: tx-sender,
            methodology: methodology,
            is-active: true
        })
        
        (ok project-id)
    )
)

;; Issue carbon credits
(define-public (issue-credits
    (project-id uint)
    (serial-number (string-ascii 50))
    (tonnage uint)
    (verification-hash (buff 32))
    (ai-confidence uint))
    (let (
        (batch-id (+ (var-get total-credits-issued) u1))
        (project (unwrap! (get-project project-id) err-invalid-project))
    )
        (asserts! (get is-active project) err-invalid-project)
        (asserts! (>= tonnage min-credit-amount) err-insufficient-credits)
        (asserts! (>= ai-confidence u80) err-verification-failed) ;; 80% minimum confidence
        
        ;; Check verifier authorization
        (let (
            (verifier (map-get? verified-entities tx-sender))
        )
            (asserts! (and (is-some verifier) 
                          (is-eq (get entity-type (unwrap-panic verifier)) "verifier")) 
                     err-not-verifier)
        )
        
        ;; Pay verification fee
        (try! (stx-transfer? verification-fee tx-sender (as-contract tx-sender)))
        
        ;; Mint NFT for batch
        (try! (nft-mint? carbon-credit-batch batch-id tx-sender))
        
        ;; Mint fungible tokens
        (try! (ft-mint? carbon-token tonnage tx-sender))
        
        ;; Create credit batch
        (map-set credit-batches batch-id {
            project-id: project-id,
            serial-number: serial-number,
            tonnage: tonnage,
            issuance-date: stacks-block-height,
            expiry-date: (+ stacks-block-height max-credit-age),
            owner: tx-sender,
            is-retired: false,
            retirement-beneficiary: none,
            verification-hash: verification-hash,
            ai-confidence-score: ai-confidence
        })
        
        ;; Update project stats
        (map-set carbon-projects project-id (merge project {
            verified-credits: (+ (get verified-credits project) tonnage)
        }))
        
        (var-set total-credits-issued (+ (var-get total-credits-issued) tonnage))
        
        (ok batch-id)
    )
)

;; List credits for sale
(define-public (list-credits
    (batch-id uint)
    (tonnage uint)
    (price-per-tonne uint)
    (min-purchase uint)
    (order-type (string-ascii 10))
    (duration uint))
    (let (
        (batch (unwrap! (get-batch batch-id) err-invalid-credit))
        (order-id (var-get total-trading-volume))
    )
        (asserts! (is-eq (get owner batch) tx-sender) err-not-verifier)
        (asserts! (not (get is-retired batch)) err-expired-credit)
        (asserts! (<= tonnage (get tonnage batch)) err-insufficient-credits)
        (asserts! (< stacks-block-height (get expiry-date batch)) err-expired-credit)
        
        (map-set market-orders order-id {
            seller: tx-sender,
            batch-id: batch-id,
            tonnage-available: tonnage,
            price-per-tonne: price-per-tonne,
            min-purchase: min-purchase,
            order-type: order-type,
            expiry-block: (+ stacks-block-height duration),
            filled: u0
        })
        
        (ok order-id)
    )
)

;; Buy carbon credits
(define-public (buy-credits
    (order-id uint)
    (tonnage uint))
    (let (
        (order (unwrap! (map-get? market-orders order-id) err-invalid-credit))
        (total-cost (* tonnage (get price-per-tonne order)))
    )
        (asserts! (>= tonnage (get min-purchase order)) err-insufficient-credits)
        (asserts! (<= tonnage (- (get tonnage-available order) (get filled order))) err-insufficient-credits)
        (asserts! (< stacks-block-height (get expiry-block order)) err-expired-credit)
        
        ;; Transfer payment
        (try! (stx-transfer? total-cost tx-sender (get seller order)))
        
        ;; Transfer carbon tokens
        (try! (ft-transfer? carbon-token tonnage (get seller order) tx-sender))
        
        ;; Update order
        (map-set market-orders order-id (merge order {
            filled: (+ (get filled order) tonnage)
        }))
        
        ;; Update trading volume
        (var-set total-trading-volume (+ (var-get total-trading-volume) tonnage))
        
        ;; Update price index (simplified moving average)
        (var-set carbon-price-index 
            (/ (+ (* (var-get carbon-price-index) u9) (get price-per-tonne order)) u10))
        
        (ok tonnage)
    )
)

;; Retire carbon credits
(define-public (retire-credits
    (batch-id uint)
    (tonnage uint)
    (beneficiary (string-ascii 100))
    (purpose (string-utf8 200)))
    (let (
        (certificate-id (+ (var-get total-credits-retired) u1))
        (batch (unwrap! (get-batch batch-id) err-invalid-credit))
    )
        ;; Burn the tokens
        (try! (ft-burn? carbon-token tonnage tx-sender))
        
        ;; Create retirement certificate
        (map-set retirement-certificates certificate-id {
            retiree: tx-sender,
            batch-id: batch-id,
            tonnage: tonnage,
            retirement-date: stacks-block-height,
            beneficiary: beneficiary,
            purpose: purpose,
            certificate-hash: (generate-certificate-hash tx-sender batch-id tonnage)
        })
        
        ;; Update batch if fully retired
        (if (is-eq tonnage (get tonnage batch))
            (map-set credit-batches batch-id (merge batch {
                is-retired: true,
                retirement-beneficiary: (some tx-sender)
            }))
            true
        )
        
        ;; Update project stats
        (let (
            (project (unwrap-panic (get-project (get project-id batch))))
        )
            (map-set carbon-projects (get project-id batch) (merge project {
                retired-credits: (+ (get retired-credits project) tonnage)
            }))
        )
        
        ;; Pay retirement bonus
        (try! (as-contract (stx-transfer? (* tonnage retirement-bonus) tx-sender tx-sender)))
        
        (var-set total-credits-retired (+ (var-get total-credits-retired) tonnage))
        
        (ok certificate-id)
    )
)

;; Register as verified entity
(define-public (register-verifier (entity-type (string-ascii 20)) (stake uint))
    (begin
        (asserts! (>= stake u100000000) err-insufficient-credits) ;; 100 STX minimum
        (asserts! (is-none (map-get? verified-entities tx-sender)) err-already-verified)
        
        (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
        
        (map-set verified-entities tx-sender {
            entity-type: entity-type,
            reputation-score: u50,
            total-verified: u0,
            disputes: u0,
            stake-amount: stake
        })
        
        (ok true)
    )
)

;; Private functions
(define-private (generate-certificate-hash (retiree principal) (batch-id uint) (tonnage uint))
    (sha256 (concat (unwrap-panic (to-consensus-buff? retiree))
                   (concat (unwrap-panic (to-consensus-buff? batch-id))
                          (unwrap-panic (to-consensus-buff? tonnage)))))
)