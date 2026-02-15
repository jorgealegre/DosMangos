---
name: ""
overview: ""
todos: []
isProject: false
---

# Group Sharing Feature - Resume Plan (2026-02-01)

## Goal

Ship group expense sharing with CloudKit sharing support, including:

- Shared group domain tables and sync wiring.
- Local mirrored personal transactions for the current user's splits.
- First-pass SwiftUI + TCA flows for groups, members, sharing, and group transactions.
- A practical base that can be iterated on for UX polish and edge-case hardening.

---

## Current Implementation Snapshot

### 1) Data model and schema status

Implemented group/shared domain models:

- `TransactionGroup` (`groups`)
- `GroupMember` (`group_members`)
- `GroupTransaction` (`group_transactions`)
- `GroupTransactionLocation` (`group_transaction_locations`)
- `GroupTransactionSplit` (`group_transaction_splits`)
- `GroupTransactionType` (`expense`, `transfer`)
- `GroupSplitType` (`equal`, `percentage`, `fixed`)

Local-only helpers:

- `LocalSetting` (`local_settings`) for storing `currentUserParticipantID`.
- `Transaction.groupTransactionSplitID` for deterministic local mirror linking.

CloudKit constraints respected:

- `group_transaction_splits` has only one FK (`groupTransactionID`).
- `memberID` is plain text/UUID column with integrity enforced by runtime triggers.

### 2) Migrations status

Group-related work was consolidated into a single migration block:

- **Migration name:** `Create groups and local mirror infrastructure`
- Creates:
  - `groups`
  - `group_members`
  - `group_transactions`
  - `group_transaction_locations`
  - `group_transaction_splits`
  - `transactions.groupTransactionSplitID` (+ index)
  - `local_settings`
  - supporting indexes on group tables

Important note:

- Consolidating multiple migrations into one is safe before broad release.
- If old migration names were already applied in production, add a compatibility strategy before shipping.

### 3) Runtime trigger strategy

Triggers are created at runtime in `Schema.swift` (`createTemporaryTriggers()`), not in migrations.

Implemented trigger groups:

- Split/member integrity triggers on local writes (`NOT isSynchronizing`):
  - Validate `memberID` exists.
  - Validate member belongs to the same group as transaction.
- Sync-time local mirror triggers (`isSynchronizing`):
  - Create/update/delete personal `transactions` rows from synced group splits.
  - Mirror `group_transaction_locations` to personal `transaction_locations`.

Mirror key behavior:

- Personal mirrored transaction ID is deterministic (`group_transaction_splits.id`).
- Uses idempotent upsert patterns to avoid duplicate local mirror rows.
- Sync-triggered mirror rows reset converted values to `NULL` so conversion pipeline can recompute.

### 4) Sync engine status

`defaultSyncEngine` now includes shared tables:

- Shared `tables`: `TransactionGroup`, `GroupMember`, `GroupTransaction`, `GroupTransactionLocation`, `GroupTransactionSplit`
- `privateTables` include existing personal/local domain tables (`Transaction`, `TransactionLocation`, `UserSettings`, categories/tags/recurring, etc.).
- `local_settings` and exchange-rate cache are intentionally local-only.

---

## GroupClient status

Implemented in `Sources/Groups/GroupClient.swift`.

### Exposed operations

- `createGroup(name, description, defaultCurrencyCode, creatorName)`
- `shareGroup(groupID)`  (updated signature from earlier memberID-based version)
- `claimMember(memberID)` (atomic claim behavior)
- `createGroupTransaction(input)`

### Key behaviors currently implemented

#### createGroup

- Creates group with `simplifyDebts = true` by default.
- Automatically creates creator member row.
- Attempts to resolve current CloudKit participant ID and sets it on creator member when available.
- Upserts `currentUserParticipantID` into `local_settings`.

#### shareGroup (latest invariant-focused behavior)

- Always resolves current user CloudKit participant ID.
- Ensures the current user is represented in that group:
  1. If a member already has this participant ID, keep/use it.
  2. Else claim first unclaimed member in that group.
  3. Else create a new member (`name = "Me"`) with this participant ID.
- Then performs `syncEngine.share(record:)`.

This enforces the requirement:

- "When I share a group, I am automatically a member and my CloudKit ID is set on the member row."

#### claimMember

- Atomic claim with `WHERE cloudKitParticipantID IS NULL`.
- Returns success/failure so UI can show conflict/retry guidance.

#### createGroupTransaction

- App-side validation:
  - non-empty splits
  - paid total equals transaction amount
  - owed total equals transaction amount
  - percentage mode totals to 100
  - transfer shape: exactly 2 members, one full payer, one full receiver
- Persists group tx + splits + optional location.
- Builds local mirror immediately for local creator when split belongs to current participant.
- Performs immediate conversion to user's default currency when possible.

---

## UI/TCA status (first iteration)

Implemented new feature module in `Sources/Groups/Groups.swift`.

### Navigation and tab

- New `Groups` tab added in app root (`Sources/App/App.swift`).
- `GroupsReducer` with navigation stack + modal destinations.

### Screens and reducers

- `GroupsView` / `GroupsReducer`
  - List all groups.
  - Toolbar add button.
- `CreateGroupView` / `CreateGroupReducer`
  - Fields: name, description, creator display name, default currency.
  - On create: calls `groupClient.createGroup`.
  - On success: dismisses and navigates to group detail.
- `GroupDetailView` / `GroupDetailReducer`
  - Group summary.
  - Members section (includes claim action).
  - Add member flow.
  - Transactions list.
  - Add transaction flow.
  - Share action now directly calls `groupClient.shareGroup(groupID)` (no pre-claim gate in UI).
- `AddMemberView` / `AddMemberReducer`
  - Basic member creation form.
- `GroupTransactionFormView` / `GroupTransactionFormReducer`
  - Transaction type: expense/transfer
  - Split mode: equal/percentage/fixed
  - Member selection
  - Paid amounts per member
  - Optional location input (lat/lon/city/country)
  - Save calls `groupClient.createGroupTransaction`.

### Current UX level

- Functional first pass, intentionally simple.
- Enough to exercise schema/sync/sharing behavior end-to-end.
- Needs polish for guided defaults, error language, transfer UX specialization, and debt visualization.

---

## File organization update

Shared-table model separation completed:

- Added `Sources/SharedModels/SharedModels.swift` for shared/group CloudKit models.
- Removed those model declarations from `Sources/SharedModels/Models.swift`.

This keeps shared-domain table definitions isolated for maintainability.

---

## Build/verification status

- Builds succeeded during implementation on iPhone 17 simulator (scheme `DosMangos`) using MCP build tools.
- Known unrelated warnings remain (iOS 26 deprecations in geocoding/local search).

---

## Main repo transfer status

Work initially done in worktree was transferred into main checkout with conflict resolution.
Conflicts resolved in:

- `Sources/SharedModels/Migrations.swift`
- `Sources/SharedModels/Schema.swift`
- later `Sources/SharedModels/Models.swift` during shared-model file move

No forced resets or destructive git operations were used.

---

## Next steps (recommended order)

1. **Polish Group Transaction form defaults**
  - Auto-fill payer amounts for common scenarios.
  - Inline sum validation UI (paid/owed/percent totals) before save.
2. **Transfer-specific UX**
  - Constrain member picker to exactly 2 participants for transfer mode.
  - Offer explicit "from member" / "to member" controls.
3. **Share/member UX**
  - Improve naming for auto-created member (`"Me"`) with safer prompt or fallback rules.
  - Optional explicit "claim as..." dialog if ambiguous.
4. **Debt summary UI**
  - Add "individual vs simplified" balance presentation in group detail.
5. **Mirror conversion refresh**
  - Ensure background conversion recalc runs for sync-triggered mirror rows with `NULL` converted fields.
6. **Hardening/tests**
  - Add integration tests for trigger behavior and claim/share invariants.
  - Add migration test coverage for consolidated migration path.

---

## Resume checklist

When resuming work:

1. Open `Sources/Groups/Groups.swift` and `Sources/Groups/GroupClient.swift`.
2. Confirm migration block `Create groups and local mirror infrastructure` in `Migrations.swift`.
3. Confirm trigger creation in `Schema.swift`.
4. Run build for `DosMangos` on iPhone 17 simulator.
5. Continue with UX polish and debt summary implementation.

