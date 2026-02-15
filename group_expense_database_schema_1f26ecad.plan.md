---
name: Group Expense Database Schema
overview: Design and implement the database schema for group expense sharing with CloudKit sharing support. Uses 5 new tables with CloudKit single-FK constraints, strict split/transfer validation, and idempotent personal mirror transactions that preserve local categories/tags.
todos:
  - id: models
    content: Add Group, GroupMember, GroupTransaction, GroupTransactionLocation, GroupTransactionSplit model structs to Models.swift
    status: pending
  - id: enums
    content: Add GroupTransactionType and SplitType enums
    status: pending
  - id: migration-tables
    content: Create migration for 5 group tables with single-FK design and indexes
    status: pending
  - id: migration-transactions
    content: Add groupTransactionSplitID column to transactions table
    status: pending
  - id: migration-local-settings
    content: Create local_settings table (non-synced) to store current user participant ID
    status: pending
  - id: triggers-validation
    content: Create triggers for memberID and cross-group integrity validation on local writes
    status: pending
  - id: triggers-personal-tx
    content: Create triggers for personal transaction creation/update/delete on CloudKit sync
    status: pending
  - id: computed
    content: Add computed properties (money, localDate, coordinate) to new models
    status: pending
  - id: sync
    content: Register group tables as shareable and move Transaction/TransactionLocation to privateTables (local_settings excluded)
    status: pending
  - id: conversion-observer
    content: Add logic to observe and fill in currency conversion for synced group transactions
    status: pending
  - id: location-sync
    content: Add triggers to propagate group_transaction_locations insert/update/delete to mirrored transaction_locations
    status: pending
  - id: split-integrity
    content: Add validation to reject save when split sums do not equal transaction total
    status: pending
  - id: transfer-rules
    content: Enforce transfer transactions to exactly 2 members (1 payer, 1 receiver)
    status: pending
  - id: member-claim
    content: Implement atomic claim flow (cloudKitParticipantID IS NULL) with retry UI on conflict
    status: pending
isProject: false
---

# Group Expense Sharing - Database Schema Plan

## Critical CloudKit Limitation

From the [SQLiteData CloudKit Sharing documentation](https://swiftpackageindex.com/pointfreeco/sqlite-data/~/documentation/sqlitedata/cloudkitsharing):

> **Only records with EXACTLY ONE foreign key can be synchronized when sharing.**
> Records with multiple foreign keys cannot be shared.

This means `group_transaction_splits` with two FKs (to `group_transactions` AND `group_members`) **will NOT sync** to other users. The solution is to:

1. Keep only ONE FK (to `group_transactions`)
2. Store `memberID` as a regular TEXT field (not a FK constraint)
3. Use **local SQLite triggers** to enforce referential integrity

## Current Architecture Summary

Your app uses:

- **SQLiteData** with `@Table` macros for models
- **CloudKit sync** infrastructure (prepared but commented out)
- **Shared PK pattern** for 1:1 relationships (e.g., `TransactionLocation`)
- **Minor units** for currency storage (`valueMinorUnits`)
- **Conversion pattern**: `convertedValueMinorUnits` / `convertedCurrencyCode`
- **Local date components**: `localYear`, `localMonth`, `localDay` for timezone stability

## Proposed Database Schema

### Table 1: `groups`

The root entity for expense sharing groups. **This is the "root record" for CloudKit sharing** (no FKs).

```swift
@Table
struct Group {
    let id: UUID
    var name: String
    var description: String
    var defaultCurrencyCode: String  // e.g., "USD"
    var simplifyDebts: Bool          // Toggle for debt simplification view
    var createdAtUTC: Date
}
```

**Notes:**

- **Root record** - no foreign keys, can be directly shared via CloudKit
- Color and image can be added later as optional fields

### Table 2: `group_members`

Members of a group (can exist before iCloud user joins). **One FK to groups** - will sync.

```swift
@Table("group_members")
struct GroupMember {
    let id: UUID
    var groupID: Group.ID              // Single FK - CloudKit compatible
    var name: String
    var cloudKitParticipantID: String? // Set when iCloud user claims this member
}
```

**Notes:**

- **One FK** to `groups` - CloudKit will sync this table when group is shared
- `cloudKitParticipantID` comes from `CKShare.Participant.userIdentity.userRecordID?.recordName`
- Members without `cloudKitParticipantID` are "unclaimed" (created by group owner)
- When a user joins via share, they select an existing member or create new, linking their participant ID
- **Index**: `idx_group_members_groupID` on `(groupID)`

### Table 3: `group_transactions`

Transactions within a group (expenses or transfers). **One FK to groups** - will sync.

```swift
@Table("group_transactions")
struct GroupTransaction {
    let id: UUID
    var groupID: Group.ID              // Single FK - CloudKit compatible
    var description: String
    var valueMinorUnits: Int           // Total amount in original currency
    var currencyCode: String           // Original currency
    var convertedValueMinorUnits: Int? // Converted to group's default currency
    var convertedCurrencyCode: String? // Group's default currency
    var type: GroupTransactionType     // .expense or .transfer
    var splitType: SplitType           // .equal, .percentage, or .fixed
    var createdAtUTC: Date
    var localYear: Int
    var localMonth: Int
    var localDay: Int
}

enum GroupTransactionType: Int {
    case expense = 0   // Normal expense split among members
    case transfer = 1  // Direct payment from one person to another
}

enum SplitType: Int {
    case equal = 0      // Divide evenly among participants
    case percentage = 1 // Each person has a percentage
    case fixed = 2      // Each person has a fixed amount
}
```

**Notes:**

- **One FK** to `groups` - CloudKit will sync this table when group is shared
- Mirrors personal `Transaction` patterns for consistency
- Conversion uses same `ExchangeRateClient` logic, converting to **group's** default currency
- **Index**: `idx_group_transactions_groupID` on `(groupID)`
- **Index**: `idx_group_transactions_localYMD` on `(localYear, localMonth, localDay, createdAtUTC)`

### Table 4: `group_transaction_locations`

Location data using shared PK pattern (1:1 with group_transactions). **One FK via shared PK** - will sync.

```swift
@Table("group_transaction_locations")
struct GroupTransactionLocation {
    @Column(primaryKey: true)
    let groupTransactionID: GroupTransaction.ID  // Shared PK = single FK - CloudKit compatible
    var latitude: Double
    var longitude: Double
    var city: String?
    var countryCode: String?
}
```

**Notes:**

- **One FK** via shared primary key pattern - CloudKit will sync this
- Identical pattern to existing `TransactionLocation`
- FK with CASCADE DELETE on `group_transactions.id`

### Table 5: `group_transaction_splits`

Tracks both what each member **paid** and what they **owe** for each transaction.

**IMPORTANT**: This table has only ONE FK (to `group_transactions`). The `memberID` is stored as TEXT without a FK constraint to satisfy CloudKit's single-FK requirement. Referential integrity is enforced via **local triggers**.

```swift
@Table("group_transaction_splits")
struct GroupTransactionSplit {
    let id: UUID
    var groupTransactionID: GroupTransaction.ID  // Single FK - CloudKit compatible
    var memberID: String                          // NOT a FK - just stores the UUID as TEXT
    var paidAmountMinorUnits: Int                 // What this member actually paid (0 if not a payer)
    var owedAmountMinorUnits: Int                 // What this member owes (their share)
    var owedPercentage: Double?                   // Only stored for percentage splits (for editing)
}
```

**SQL Schema:**

```sql
CREATE TABLE "group_transaction_splits" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "groupTransactionID" TEXT NOT NULL REFERENCES "group_transactions"("id") ON DELETE CASCADE,
  "memberID" TEXT NOT NULL,  -- No FK constraint! Enforced by trigger
  "paidAmountMinorUnits" INTEGER NOT NULL,
  "owedAmountMinorUnits" INTEGER NOT NULL,
  "owedPercentage" REAL
) STRICT
```

**Notes:**

- **One FK** to `group_transactions` only - CloudKit will sync this table
- `memberID` is TEXT (not a FK) - integrity enforced by local triggers
- A row exists for each **participant** in the transaction
- For **expenses**: multiple payers can each have `paidAmountMinorUnits > 0`
- For **transfers**: payer has `paidAmount = total, owedAmount = 0`; receiver has `paidAmount = 0, owedAmount = total`
- **Validation**: `sum(paidAmountMinorUnits)` must equal `transaction.valueMinorUnits`
- **Index**: `idx_group_transaction_splits_groupTransactionID` on `(groupTransactionID)`
- **Index**: `idx_group_transaction_splits_memberID` on `(memberID)`

### Table 6: Modified `transactions` table

Add a column to link personal transactions back to group transaction splits:

```sql
ALTER TABLE "transactions"
ADD COLUMN "groupTransactionSplitID" TEXT
-- No FK constraint for CloudKit compatibility
```

This column links a personal transaction to its source group transaction split, enabling:

- Querying which personal transactions came from groups
- Updating/deleting personal transactions when group splits change

## Entity Relationship Diagram

```mermaid
erDiagram
    groups ||--o{ group_members : has
    groups ||--o{ group_transactions : has
    group_transactions ||--o| group_transaction_locations : has
    group_transactions ||--o{ group_transaction_splits : has
    group_members ||--o{ group_transaction_splits : "participates (via trigger)"
    group_transaction_splits ||--o| transactions : "creates personal copy"
    local_settings ||--|| group_members : "identifies current user"

    groups {
        UUID id PK
        TEXT name
        TEXT description
        TEXT defaultCurrencyCode
        INTEGER simplifyDebts
        TEXT createdAtUTC
    }

    group_members {
        UUID id PK
        UUID groupID FK
        TEXT name
        TEXT cloudKitParticipantID
    }

    group_transactions {
        UUID id PK
        UUID groupID FK
        TEXT description
        INTEGER valueMinorUnits
        TEXT currencyCode
        INTEGER convertedValueMinorUnits
        TEXT convertedCurrencyCode
        INTEGER type
        INTEGER splitType
        TEXT createdAtUTC
        INTEGER localYear
        INTEGER localMonth
        INTEGER localDay
    }

    group_transaction_locations {
        UUID groupTransactionID PK_FK
        REAL latitude
        REAL longitude
        TEXT city
        TEXT countryCode
    }

    group_transaction_splits {
        UUID id PK
        UUID groupTransactionID FK
        TEXT memberID "no FK - trigger enforced"
        INTEGER paidAmountMinorUnits
        INTEGER owedAmountMinorUnits
        REAL owedPercentage
    }

    transactions {
        UUID id PK
        TEXT groupTransactionSplitID "links to group"
        TEXT description
        INTEGER valueMinorUnits
        TEXT currencyCode
    }

    local_settings {
        TEXT key PK
        TEXT value
    }
```



**Note**: `local_settings` is a local-only table (not synced). It stores `currentUserParticipantID` which is used by triggers to identify which group member is "me" on this device.

## Local Triggers for Data Integrity

Since `memberID` in `group_transaction_splits` cannot be a FK (CloudKit limitation), we use local triggers to enforce integrity. These triggers use `WHEN NOT isSynchronizing()` to only run for local writes, not CloudKit sync.

### Trigger 1: Validate memberID and group integrity on INSERT

```sql
CREATE TRIGGER "validate_split_member_insert"
BEFORE INSERT ON "group_transaction_splits"
FOR EACH ROW WHEN NOT isSynchronizing()
BEGIN
  SELECT RAISE(ABORT, 'Invalid memberID: member does not exist')
  WHERE NOT EXISTS (
    SELECT 1 FROM "group_members" WHERE "id" = NEW."memberID"
  );
  SELECT RAISE(ABORT, 'Invalid split: member does not belong to transaction group')
  WHERE NOT EXISTS (
    SELECT 1
    FROM "group_members" gm
    JOIN "group_transactions" gt ON gt."id" = NEW."groupTransactionID"
    WHERE gm."id" = NEW."memberID"
      AND gm."groupID" = gt."groupID"
  );
END
```

### Trigger 2: Validate memberID and group integrity on UPDATE

```sql
CREATE TRIGGER "validate_split_member_update"
BEFORE UPDATE ON "group_transaction_splits"
FOR EACH ROW WHEN NOT isSynchronizing() AND NEW."memberID" != OLD."memberID"
BEGIN
  SELECT RAISE(ABORT, 'Invalid memberID: member does not exist')
  WHERE NOT EXISTS (
    SELECT 1 FROM "group_members" WHERE "id" = NEW."memberID"
  );
  SELECT RAISE(ABORT, 'Invalid split: member does not belong to transaction group')
  WHERE NOT EXISTS (
    SELECT 1
    FROM "group_members" gm
    JOIN "group_transactions" gt ON gt."id" = NEW."groupTransactionID"
    WHERE gm."id" = NEW."memberID"
      AND gm."groupID" = gt."groupID"
  );
END
```

## Personal Transaction Creation

Personal transactions need to be created in TWO scenarios:

1. **Local creates**: When YOU create a group transaction that includes yourself
2. **Synced creates**: When ANOTHER user creates a group transaction that includes you, and it syncs to your device

### Solution: Local Settings Table + Triggers

To handle synced creates, we need a way for SQLite triggers to know "who is me". We'll store this in a **local-only table** (not synced):

### Table 7: `local_settings` (NOT synced)

```sql
CREATE TABLE "local_settings" (
  "key" TEXT PRIMARY KEY NOT NULL,
  "value" TEXT NOT NULL
) STRICT
```

Store the current user's CloudKit participant ID:

```swift
// On app launch / sign-in
try database.write { db in
    let participantID = try await CKContainer.default().userRecordID().recordName
    try #sql("""
        INSERT OR REPLACE INTO local_settings (key, value)
        VALUES ('currentUserParticipantID', \(bind: participantID))
    """).execute(db)
}
```

### Trigger: Create personal transaction when synced splits arrive

This trigger fires when CloudKit syncs a new split that affects "me". It is idempotent and avoids duplicate mirrors:

```sql
CREATE TRIGGER "create_personal_from_synced_split"
AFTER INSERT ON "group_transaction_splits"
FOR EACH ROW WHEN isSynchronizing()  -- Only for CloudKit sync, not local writes
BEGIN
  INSERT INTO "transactions" (
    "id",
    "description",
    "valueMinorUnits",
    "currencyCode",
    "type",
    "createdAtUTC",
    "localYear",
    "localMonth",
    "localDay",
    "groupTransactionSplitID"
    -- convertedValueMinorUnits and convertedCurrencyCode left as NULL
  )
  SELECT
    NEW."id",  -- deterministic mirror ID
    gt."description",
    NEW."owedAmountMinorUnits",
    gt."currencyCode",
    0,  -- expense type
    gt."createdAtUTC",
    gt."localYear",
    gt."localMonth",
    gt."localDay",
    NEW."id"
  FROM "group_transactions" gt
  JOIN "group_members" gm ON gm."id" = NEW."memberID"
  JOIN "local_settings" ls ON ls."key" = 'currentUserParticipantID'
  WHERE gt."id" = NEW."groupTransactionID"
    AND gm."cloudKitParticipantID" = ls."value"
  ON CONFLICT("id") DO UPDATE SET
    "description" = excluded."description",
    "valueMinorUnits" = excluded."valueMinorUnits",
    "currencyCode" = excluded."currencyCode",
    "type" = excluded."type",
    "createdAtUTC" = excluded."createdAtUTC",
    "localYear" = excluded."localYear",
    "localMonth" = excluded."localMonth",
    "localDay" = excluded."localDay",
    "groupTransactionSplitID" = excluded."groupTransactionSplitID";

  INSERT INTO "transaction_locations" (
    "transactionID",
    "latitude",
    "longitude",
    "city",
    "countryCode"
  )
  SELECT
    t."id",
    gtl."latitude",
    gtl."longitude",
    gtl."city",
    gtl."countryCode"
  FROM "transactions" t
  JOIN "group_transaction_splits" gts ON gts."id" = t."groupTransactionSplitID"
  JOIN "group_transaction_locations" gtl ON gtl."groupTransactionID" = gts."groupTransactionID"
  WHERE t."groupTransactionSplitID" = NEW."id"
    AND NOT EXISTS (
      SELECT 1
      FROM "transaction_locations" tl
      WHERE tl."transactionID" = t."id"
    );
END
```

### Trigger: Update personal transaction when synced splits update

```sql
CREATE TRIGGER "update_personal_from_synced_split"
AFTER UPDATE ON "group_transaction_splits"
FOR EACH ROW WHEN isSynchronizing()
BEGIN
  UPDATE "transactions"
  SET
    "valueMinorUnits" = NEW."owedAmountMinorUnits",
    "convertedValueMinorUnits" = NULL,  -- Mark for re-conversion
    "convertedCurrencyCode" = NULL
  WHERE "groupTransactionSplitID" = NEW."id";

  UPDATE "transaction_locations"
  SET
    "latitude" = (
      SELECT gtl."latitude"
      FROM "group_transaction_locations" gtl
      WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
    ),
    "longitude" = (
      SELECT gtl."longitude"
      FROM "group_transaction_locations" gtl
      WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
    ),
    "city" = (
      SELECT gtl."city"
      FROM "group_transaction_locations" gtl
      WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
    ),
    "countryCode" = (
      SELECT gtl."countryCode"
      FROM "group_transaction_locations" gtl
      WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
    )
  WHERE "transactionID" = (
    SELECT t."id"
    FROM "transactions" t
    WHERE t."groupTransactionSplitID" = NEW."id"
  );
END
```

### Additional location propagation triggers

Location can change without split changes, so add triggers on `group_transaction_locations`:

- `AFTER INSERT` -> upsert `transaction_locations` for all mirrored transactions of that group transaction
- `AFTER UPDATE` -> overwrite mirrored `transaction_locations`
- `AFTER DELETE` -> delete mirrored `transaction_locations`

### Trigger: Delete personal transaction when synced splits are deleted

```sql
CREATE TRIGGER "delete_personal_from_synced_split"
AFTER DELETE ON "group_transaction_splits"
FOR EACH ROW WHEN isSynchronizing()
BEGIN
  DELETE FROM "transaction_locations"
  WHERE "transactionID" IN (
    SELECT t."id"
    FROM "transactions" t
    WHERE t."groupTransactionSplitID" = OLD."id"
  );
  DELETE FROM "transactions"
  WHERE "groupTransactionSplitID" = OLD."id";
END
```

### Currency Conversion Flow

The synced trigger creates personal transactions with `convertedValueMinorUnits = NULL`. The app then:

1. **Observes transactions** where `groupTransactionSplitID IS NOT NULL AND convertedValueMinorUnits IS NULL`
2. **Fetches exchange rates** and fills in the converted values
3. This mirrors existing behavior for personal transactions created while offline

### Local Creates (App Code)

When YOU create a group transaction locally, handle personal transaction creation in app code:

- Immediate currency conversion using `ExchangeRateClient`
- Set both original and converted values
- Copy location from `group_transaction_locations` into `transaction_locations`
- Better error handling

See "Implementation Decisions" section for the detailed app code flow.

### Editable Local Mirror Rules

Local mirror transactions are editable, but with field-level rules:

- **Synced/owned by group (always overwritten from group):**
  - `description`
  - `valueMinorUnits`
  - `currencyCode`
  - `convertedValueMinorUnits`
  - `convertedCurrencyCode`
  - `type`
  - `createdAtUTC`
  - `localYear`, `localMonth`, `localDay`
  - `transaction_locations` (latitude/longitude/city/countryCode)
- **Local-only user edits (preserved):**
  - categories (`transactionsCategories`)
  - tags (`transactionsTags`)

### Mirror Field Protection Strategy

Keep this simple:

- **UI hard block only**: personal transaction form disables editing of group-owned fields when `groupTransactionSplitID` is set.
- Sync/app mirror updates still overwrite group-owned fields, while local categories/tags remain editable and preserved.

## Balance Calculation Logic

## Save-Time Validation Rules (Reject on Failure)

All local writes for `group_transactions` + `group_transaction_splits` must run inside one transaction and be validated before commit:

1. `sum(paidAmountMinorUnits)` for the transaction must equal `group_transactions.valueMinorUnits`
2. `sum(owedAmountMinorUnits)` for the transaction must equal `group_transactions.valueMinorUnits`
3. `splitType == .percentage` requires total percentage = 100 (with deterministic rounding strategy)
4. `splitType == .equal` ignores percentages and computes deterministic remainders
5. `type == .transfer` requires exactly 2 splits:
  - one member with `paidAmountMinorUnits == total` and `owedAmountMinorUnits == 0`
  - one member with `paidAmountMinorUnits == 0` and `owedAmountMinorUnits == total`
6. Any validation failure aborts save and surfaces a user-facing error

These checks are implemented in app save logic (authoritative) and can be optionally duplicated with SQL triggers for local writes.

For each member, their balance is computed as:

```
memberBalance = sum(paidAmountMinorUnits) - sum(owedAmountMinorUnits)
```

- **Positive balance**: Others owe them money (they paid more than their share)
- **Negative balance**: They owe the group (they owe more than they paid)

### Individual Debts View

Calculate pairwise debts from all transactions, showing "Alice owes Bob $20".

### Simplified Debts View

Apply debt simplification algorithm (when `group.simplifyDebts == true`):

1. Calculate net balance for each member
2. Sort into creditors (positive) and debtors (negative)
3. Match debtors to creditors to minimize total transactions

## Querying User's Group Transactions

**Option A**: Query group splits directly (no personal transaction copy needed):

```sql
SELECT gt.*, gm.name as memberName, gts.owedAmountMinorUnits
FROM group_transactions gt
JOIN group_members gm ON gm.groupID = gt.groupID
JOIN group_transaction_splits gts ON gts.groupTransactionID = gt.id
    AND gts.memberID = gm.id
WHERE gm.cloudKitParticipantID = :currentUserParticipantID
ORDER BY gt.localYear DESC, gt.localMonth DESC, gt.localDay DESC, gt.createdAtUTC DESC
```

**Option B**: Query personal transactions that came from groups:

```sql
SELECT t.*, gts.*, gt.description as groupDescription
FROM transactions t
JOIN group_transaction_splits gts ON gts.id = t.groupTransactionSplitID
JOIN group_transactions gt ON gt.id = gts.groupTransactionID
WHERE t.groupTransactionSplitID IS NOT NULL
```

## CloudKit Sharing Setup

Register new tables in `SyncEngine`. Note that all group tables have **exactly one FK** (or zero for the root):

```swift
defaultSyncEngine = try SyncEngine(
    for: defaultDatabase,
    tables:
        Group.self,                    // ROOT - 0 FKs - shareable
        GroupMember.self,              // 1 FK to Group - will sync
        GroupTransaction.self,         // 1 FK to Group - will sync
        GroupTransactionLocation.self, // 1 FK (shared PK) - will sync
        GroupTransactionSplit.self,    // 1 FK to GroupTransaction - will sync
    privateTables:
        Transaction.self,              // private-only personal transactions
        TransactionLocation.self,      // private-only personal locations
        UserSettings.self,
        // ... existing private tables
    // NOTE: local_settings is NOT registered - it's purely local
)
```

**Key insights**:

- `GroupTransactionSplit.memberID` is NOT a FK at the SQL level, so CloudKit sees it as having only 1 FK (to `group_transactions`). This is the workaround for CloudKit's single-FK limitation.
- Personal `Transaction` and `TransactionLocation` tables are private-only and not shared with group participants.
- `local_settings` table is **not registered** with SyncEngine - it stores device-local data only (current user's participant ID)

## Edge Cases and Constraints


| Scenario                       | Handling                                                                                  |
| ------------------------------ | ----------------------------------------------------------------------------------------- |
| Group hard delete              | CASCADE DELETE all related tables (use sparingly)                                         |
| Rounding in equal splits       | Last participant gets the remainder (e.g., 100/3 = 33, 33, 34)                            |
| Currency conversion fails      | `convertedValueMinorUnits = nil`, exclude from balance calcs until converted              |
| Two users claim same member    | Second claim fails; app shows retry UI (choose another member or create new)              |
| User leaves shared group       | CloudKit handles removal; their `cloudKitParticipantID` stays for history                 |
| memberID integrity             | Trigger validates memberID exists and belongs to same group as transaction                |
| Duplicate personal mirror      | Deterministic mirror ID (`transactions.id = groupTransactionSplitID`) + idempotent upsert |
| Split totals mismatch          | Save is rejected if paid or owed sums do not equal transaction total                      |
| Transfer shape invalid         | Save is rejected unless exactly 2 members (1 payer, 1 receiver)                           |
| Sync receives invalid memberID | No trigger fires (isSynchronizing=true); data stored as-is; app handles gracefully        |


## Migration Plan

Add new migrations in [Migrations.swift](Sources/SharedModels/Migrations.swift):

### Migration 1: Create group tables

```swift
migrator.registerMigration("Create group expense tables") { db in
    // 1. Create groups table (root record - no FKs)
    try #sql("""
        CREATE TABLE "groups" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "name" TEXT NOT NULL,
            "description" TEXT NOT NULL DEFAULT '',
            "defaultCurrencyCode" TEXT NOT NULL DEFAULT 'USD',
            "simplifyDebts" INTEGER NOT NULL DEFAULT 0,
            "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now'))
        ) STRICT
    """).execute(db)

    // 2. Create group_members table (1 FK to groups)
    try #sql("""
        CREATE TABLE "group_members" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "groupID" TEXT NOT NULL REFERENCES "groups"("id") ON DELETE CASCADE,
            "name" TEXT NOT NULL,
            "cloudKitParticipantID" TEXT
        ) STRICT
    """).execute(db)

    // 3. Create group_transactions table (1 FK to groups)
    try #sql("""
        CREATE TABLE "group_transactions" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "groupID" TEXT NOT NULL REFERENCES "groups"("id") ON DELETE CASCADE,
            "description" TEXT NOT NULL,
            "valueMinorUnits" INTEGER NOT NULL,
            "currencyCode" TEXT NOT NULL,
            "convertedValueMinorUnits" INTEGER,
            "convertedCurrencyCode" TEXT,
            "type" INTEGER NOT NULL DEFAULT 0,
            "splitType" INTEGER NOT NULL DEFAULT 0,
            "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
            "localYear" INTEGER NOT NULL,
            "localMonth" INTEGER NOT NULL,
            "localDay" INTEGER NOT NULL
        ) STRICT
    """).execute(db)

    // 4. Create group_transaction_locations table (shared PK pattern)
    try #sql("""
        CREATE TABLE "group_transaction_locations" (
            "groupTransactionID" TEXT PRIMARY KEY NOT NULL
                REFERENCES "group_transactions"("id") ON DELETE CASCADE,
            "latitude" REAL NOT NULL,
            "longitude" REAL NOT NULL,
            "city" TEXT,
            "countryCode" TEXT
        ) STRICT
    """).execute(db)

    // 5. Create group_transaction_splits table (1 FK only - memberID is NOT a FK!)
    try #sql("""
        CREATE TABLE "group_transaction_splits" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "groupTransactionID" TEXT NOT NULL
                REFERENCES "group_transactions"("id") ON DELETE CASCADE,
            "memberID" TEXT NOT NULL,
            "paidAmountMinorUnits" INTEGER NOT NULL,
            "owedAmountMinorUnits" INTEGER NOT NULL,
            "owedPercentage" REAL
        ) STRICT
    """).execute(db)

    // 6. Create indexes
    try #sql("CREATE INDEX idx_group_members_groupID ON group_members(groupID)").execute(db)
    try #sql("CREATE INDEX idx_group_transactions_groupID ON group_transactions(groupID)").execute(db)
    try #sql("""
        CREATE INDEX idx_group_transactions_localYMD
        ON group_transactions(localYear, localMonth, localDay, createdAtUTC)
    """).execute(db)
    try #sql("""
        CREATE INDEX idx_group_transaction_splits_groupTransactionID
        ON group_transaction_splits(groupTransactionID)
    """).execute(db)
    try #sql("""
        CREATE INDEX idx_group_transaction_splits_memberID
        ON group_transaction_splits(memberID)
    """).execute(db)
}
```

### Migration 2: Add groupTransactionSplitID to transactions

```swift
migrator.registerMigration("Add group link to transactions") { db in
    try #sql("""
        ALTER TABLE "transactions"
        ADD COLUMN "groupTransactionSplitID" TEXT
    """).execute(db)

    try #sql("""
        CREATE INDEX idx_transactions_groupTransactionSplitID
        ON transactions(groupTransactionSplitID)
    """).execute(db)
}
```

### Migration 3: Create local_settings table (NOT synced)

```swift
migrator.registerMigration("Create local settings table") { db in
    try #sql("""
        CREATE TABLE "local_settings" (
            "key" TEXT PRIMARY KEY NOT NULL,
            "value" TEXT NOT NULL
        ) STRICT
    """).execute(db)
}
```

### Migration 4: Create triggers for memberID integrity

```swift
migrator.registerMigration("Create memberID validation triggers") { db in
    // Trigger to validate memberID + same-group integrity on INSERT (only for local writes)
    try #sql("""
        CREATE TRIGGER "validate_split_member_insert"
        BEFORE INSERT ON "group_transaction_splits"
        FOR EACH ROW WHEN NOT \(SyncEngine.$isSynchronizing)
        BEGIN
            SELECT RAISE(ABORT, 'Invalid memberID: member does not exist')
            WHERE NOT EXISTS (
                SELECT 1 FROM "group_members" WHERE "id" = NEW."memberID"
            );
            SELECT RAISE(ABORT, 'Invalid split: member does not belong to transaction group')
            WHERE NOT EXISTS (
                SELECT 1
                FROM "group_members" gm
                JOIN "group_transactions" gt ON gt."id" = NEW."groupTransactionID"
                WHERE gm."id" = NEW."memberID"
                  AND gm."groupID" = gt."groupID"
            );
        END
    """).execute(db)

    // Trigger to validate memberID + same-group integrity on UPDATE (only for local writes)
    try #sql("""
        CREATE TRIGGER "validate_split_member_update"
        BEFORE UPDATE ON "group_transaction_splits"
        FOR EACH ROW WHEN NOT \(SyncEngine.$isSynchronizing)
            AND NEW."memberID" != OLD."memberID"
        BEGIN
            SELECT RAISE(ABORT, 'Invalid memberID: member does not exist')
            WHERE NOT EXISTS (
                SELECT 1 FROM "group_members" WHERE "id" = NEW."memberID"
            );
            SELECT RAISE(ABORT, 'Invalid split: member does not belong to transaction group')
            WHERE NOT EXISTS (
                SELECT 1
                FROM "group_members" gm
                JOIN "group_transactions" gt ON gt."id" = NEW."groupTransactionID"
                WHERE gm."id" = NEW."memberID"
                  AND gm."groupID" = gt."groupID"
            );
        END
    """).execute(db)
}
```

### Migration 5: Create triggers for personal transaction creation from synced splits

```swift
migrator.registerMigration("Create personal transaction sync triggers") { db in
    // Create personal transaction when CloudKit syncs a split that affects "me"
    try #sql("""
        CREATE TRIGGER "create_personal_from_synced_split"
        AFTER INSERT ON "group_transaction_splits"
        FOR EACH ROW WHEN \(SyncEngine.$isSynchronizing)
        BEGIN
            INSERT INTO "transactions" (
                "id",
                "description",
                "valueMinorUnits",
                "currencyCode",
                "type",
                "createdAtUTC",
                "localYear",
                "localMonth",
                "localDay",
                "groupTransactionSplitID"
            )
            SELECT
                NEW."id",  -- deterministic mirror ID avoids duplicates
                gt."description",
                NEW."owedAmountMinorUnits",
                gt."currencyCode",
                0,
                gt."createdAtUTC",
                gt."localYear",
                gt."localMonth",
                gt."localDay",
                NEW."id"
            FROM "group_transactions" gt
            JOIN "group_members" gm ON gm."id" = NEW."memberID"
            JOIN "local_settings" ls ON ls."key" = 'currentUserParticipantID'
            WHERE gt."id" = NEW."groupTransactionID"
                AND gm."cloudKitParticipantID" = ls."value"
            ON CONFLICT("id") DO UPDATE SET
                "description" = excluded."description",
                "valueMinorUnits" = excluded."valueMinorUnits",
                "currencyCode" = excluded."currencyCode",
                "type" = excluded."type",
                "createdAtUTC" = excluded."createdAtUTC",
                "localYear" = excluded."localYear",
                "localMonth" = excluded."localMonth",
                "localDay" = excluded."localDay",
                "groupTransactionSplitID" = excluded."groupTransactionSplitID";

            INSERT INTO "transaction_locations" (
                "transactionID",
                "latitude",
                "longitude",
                "city",
                "countryCode"
            )
            SELECT
                t."id",
                gtl."latitude",
                gtl."longitude",
                gtl."city",
                gtl."countryCode"
            FROM "transactions" t
            JOIN "group_transaction_splits" gts ON gts."id" = t."groupTransactionSplitID"
            JOIN "group_transaction_locations" gtl ON gtl."groupTransactionID" = gts."groupTransactionID"
            WHERE t."groupTransactionSplitID" = NEW."id"
                AND NOT EXISTS (
                    SELECT 1
                    FROM "transaction_locations" tl
                    WHERE tl."transactionID" = t."id"
                );
        END
    """).execute(db)

    // Update personal transaction when synced split changes
    try #sql("""
        CREATE TRIGGER "update_personal_from_synced_split"
        AFTER UPDATE ON "group_transaction_splits"
        FOR EACH ROW WHEN \(SyncEngine.$isSynchronizing)
        BEGIN
            UPDATE "transactions"
            SET
                "valueMinorUnits" = NEW."owedAmountMinorUnits",
                "convertedValueMinorUnits" = NULL,
                "convertedCurrencyCode" = NULL
            WHERE "groupTransactionSplitID" = NEW."id";

            UPDATE "transaction_locations"
            SET
                "latitude" = (
                    SELECT gtl."latitude"
                    FROM "group_transaction_locations" gtl
                    WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
                ),
                "longitude" = (
                    SELECT gtl."longitude"
                    FROM "group_transaction_locations" gtl
                    WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
                ),
                "city" = (
                    SELECT gtl."city"
                    FROM "group_transaction_locations" gtl
                    WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
                ),
                "countryCode" = (
                    SELECT gtl."countryCode"
                    FROM "group_transaction_locations" gtl
                    WHERE gtl."groupTransactionID" = NEW."groupTransactionID"
                )
            WHERE "transactionID" = (
                SELECT t."id"
                FROM "transactions" t
                WHERE t."groupTransactionSplitID" = NEW."id"
            );
        END
    """).execute(db)

    // Delete personal transaction when synced split is deleted
    try #sql("""
        CREATE TRIGGER "delete_personal_from_synced_split"
        AFTER DELETE ON "group_transaction_splits"
        FOR EACH ROW WHEN \(SyncEngine.$isSynchronizing)
        BEGIN
            DELETE FROM "transaction_locations"
            WHERE "transactionID" IN (
                SELECT t."id"
                FROM "transactions" t
                WHERE t."groupTransactionSplitID" = OLD."id"
            );
            DELETE FROM "transactions"
            WHERE "groupTransactionSplitID" = OLD."id";
        END
    """).execute(db)
}
```

## Files to Modify

- [Sources/SharedModels/Models.swift](Sources/SharedModels/Models.swift) - Add new model structs
- [Sources/SharedModels/Migrations.swift](Sources/SharedModels/Migrations.swift) - Add migrations and triggers
- [Sources/SharedModels/Schema.swift](Sources/SharedModels/Schema.swift) - Register tables with SyncEngine, register custom SQL functions

## What This Schema Does NOT Handle (As Requested)

- Categories and tags for group transactions
- Recurring group transactions
- Group member avatars/colors (can add later)
- Group images (can add later)

## Implementation Decisions

### Personal Transaction Creation (Hybrid: App Code + Sync Triggers)

Personal transactions are created by:

- **App code** for local creates/edits (immediate conversion and full control)
- **SQLite sync triggers** for records arriving from CloudKit

App code remains important because:

1. **Access to current user**: Can get `cloudKitParticipantID` from `CKContainer.default().userRecordID()` or from `CKShare.currentUserParticipant` via SyncMetadata
2. **Currency conversion**: Can use existing `ExchangeRateClient` to convert to user's default currency immediately
3. **Flexibility**: Easier to handle edge cases and error recovery

**Flow when saving a group transaction split:**

```swift
// In GroupTransactionForm reducer or similar
func saveGroupTransactionWithSplits(...) async throws {
    // 1. Save the group transaction and splits to database
    let groupTransaction = try await database.write { db in
        // ... save group transaction and splits
    }

    // 2. Find which split belongs to "me"
    let currentUserParticipantID = try await getCurrentUserParticipantID()
    let mySplit = splits.first { split in
        let member = members[split.memberID]
        return member?.cloudKitParticipantID == currentUserParticipantID
    }

    // 3. If I have a split, create/update personal transaction mirror
    if let mySplit {
        let userDefaultCurrency = userSettings.defaultCurrency
        let convertedAmount = try await exchangeRate.convert(
            mySplit.owedAmountMinorUnits,
            from: groupTransaction.currencyCode,
            to: userDefaultCurrency
        )

        try await database.write { db in
            // Use deterministic mirror ID: transaction.id == groupTransactionSplitID.
            // Upsert mirror row: overwrite group-owned fields, preserve local categories/tags.
            // Then upsert transaction_locations from group_transaction_locations.
        }
    }
}
```

### Getting Current User's Participant ID

To identify "me" in a group, use CloudKit to get the current user's record ID:

```swift
func getCurrentUserParticipantID() async throws -> String {
    let container = CKContainer.default()
    let userRecordID = try await container.userRecordID()
    return userRecordID.recordName
}
```

This `recordName` is what gets stored in `GroupMember.cloudKitParticipantID` when a user claims a member.

### Automatic Recompute Policy

When `userSettings.defaultCurrency` changes, recompute converted values for all personal transactions, including mirrored group transactions:

1. Recompute `convertedValueMinorUnits` and `convertedCurrencyCode` for every row in `transactions`
2. Preserve categories/tags and all mirror linkage (`groupTransactionSplitID`)
3. Recompute in background with progress/error handling and retry support

### Member Claim (Atomic, Fail-Fast)

Claiming a placeholder member must be a single conditional write:

```swift
let rowsUpdated = try await database.write { db in
  try GroupMember
    .find(memberID)
    .where { $0.cloudKitParticipantID == nil }
    .update { $0.cloudKitParticipantID = currentUserParticipantID }
    .execute(db)
}
guard rowsUpdated > 0 else {
  // Claim lost race -> show retry UI:
  // pick another unclaimed member or create a new one
  return
}
```

This guarantees the second claim fails cleanly without corrupting ownership.

### Query Style

Use StructuredQueries builders for app queries and business logic.

- Use `#sql` for migrations/triggers and schema DDL
- Keep runtime reads/writes type-safe via StructuredQueries + SQLiteData

### memberID Validation Triggers (Keep in SQLite)

The triggers for validating `memberID` stay as pure SQL since they only need database access:

```sql
CREATE TRIGGER "validate_split_member_insert"
BEFORE INSERT ON "group_transaction_splits"
FOR EACH ROW WHEN NOT isSynchronizing()
BEGIN
  SELECT RAISE(ABORT, 'Invalid memberID: member does not exist')
  WHERE NOT EXISTS (
    SELECT 1 FROM "group_members" WHERE "id" = NEW."memberID"
  );
END
```

