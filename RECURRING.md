# Recurring Transactions

This document describes how recurring transactions work in DosMangos and serves as the implementation plan.

---

## Overview

Recurring transactions allow users to define transaction "templates" that repeat on a schedule. Instead of automatically creating transactions, the system shows **virtual instances** that the user can **Post** (create a real transaction) or **Skip**.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Recurring Transaction** | A template defining what a transaction looks like + how often it repeats |
| **Virtual Instance** | A UI representation of a due occurrence (not stored in DB) |
| **Posted Transaction** | A real transaction created from a virtual instance |
| **Occurrence** | A single instance in time when the recurring transaction is due |

---

## Data Model

### `recurringTransactions` Table

Stores the template definition and recurrence rules. Note: No locationID — location is captured from user's current location when posting.

```
id                      UUID PRIMARY KEY
description             TEXT
valueMinorUnits         INTEGER
currencyCode            TEXT
type                    INTEGER (expense/income)

-- Recurrence Rule (flattened)
frequency               INTEGER (daily=0, weekly=1, monthly=2, yearly=3)
interval                INTEGER (every N units)
weeklyDays              TEXT? (comma-separated: "2,4,6" for Mon,Wed,Fri)
monthlyMode             INTEGER? (each=0, onThe=1)
monthlyDays             TEXT? (comma-separated: "1,15" for 1st and 15th)
monthlyOrdinal          INTEGER? (first=1, second=2, third=3, fourth=4, last=-1)
monthlyWeekday          INTEGER? (sunday=1 through saturday=7)
yearlyMonths            TEXT? (comma-separated: "1,7" for Jan,Jul)
yearlyDaysOfWeekEnabled INTEGER (0 or 1)
yearlyOrdinal           INTEGER?
yearlyWeekday           INTEGER?
endMode                 INTEGER (never=0, onDate=1, afterOccurrences=2)
endDate                 TEXT? (ISO date)
endAfterOccurrences     INTEGER?

-- State
startDate               TEXT (when recurrence begins)
nextDueDate             TEXT (the next occurrence to show)
postedCount             INTEGER (how many have been posted)
status                  INTEGER (active=0, paused=1, completed=2, deleted=3)

-- Metadata
createdAtUTC            TEXT
updatedAtUTC            TEXT
```

### `recurringTransactionsCategories` Table

Join table for categories (similar to `transactionsCategories`).

```
id                      UUID PRIMARY KEY
recurringTransactionID  UUID (FK to recurringTransactions)
categoryID              TEXT (FK to categories)
```

### `recurringTransactionsTags` Table

Join table for tags (similar to `transactionsTags`).

```
id                      UUID PRIMARY KEY
recurringTransactionID  UUID (FK to recurringTransactions)
tagID                   TEXT (FK to tags)
```

### `transactions` Table (Addition)

Add a nullable foreign key to link posted transactions back to their template.

```
recurringTransactionID  UUID? (FK to recurringTransactions)
```

---

## Status Lifecycle

```
                    ┌─────────────┐
                    │   active    │ ← Normal operating state
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │   paused   │  │ completed  │  │  deleted   │
    └────────────┘  └────────────┘  └────────────┘
           │               │
           └───────┬───────┘
                   ▼
            (can reactivate)
```

- **active**: Virtual instances are shown when due
- **paused**: User temporarily stopped; no virtual instances shown
- **completed**: End condition met (date or occurrence count); no more instances
- **deleted**: Soft delete; template preserved for history but no longer active

---

## UI Flows

### Transactions List (Home Tab)

```
┌─────────────────────────────────────────┐
│  📋 Due (3)                        ▼    │  ← Collapsible section
├─────────────────────────────────────────┤
│  🔄 Netflix Subscription                │
│     $15.99 · Monthly · Due Jan 1        │
│     [Post]  [Skip]                      │
├─────────────────────────────────────────┤
│  🔄 Gym Membership                      │
│     $40.00 · Monthly · Due Jan 1        │
│     [Post]  [Skip]                      │
├─────────────────────────────────────────┤
│  🔄 Daily Coffee (3 due)                │  ← Shows count when multiple
│     $5.00 · Daily · Due Jan 3           │
│     [Post]  [Skip]                      │
├─────────────────────────────────────────┤
│                                         │
│  Today                                  │
├─────────────────────────────────────────┤
│  ☕ Coffee                    -$5.00    │
│  🔄                                     │  ← Recurring symbol
├─────────────────────────────────────────┤
│  🛒 Groceries                -$45.00    │
├─────────────────────────────────────────┤
│  Yesterday                              │
├─────────────────────────────────────────┤
│  ...                                    │
└─────────────────────────────────────────┘
```

### Recurring Tab

Shows all recurring transaction templates.

```
┌─────────────────────────────────────────┐
│  Recurring Transactions           [+]   │
├─────────────────────────────────────────┤
│  Netflix Subscription                   │
│  $15.99 · Monthly on the 1st           │
│  Next: Feb 1                            │
├─────────────────────────────────────────┤
│  Gym Membership                         │
│  $40.00 · Monthly on the 1st           │
│  Next: Feb 1                            │
├─────────────────────────────────────────┤
│  Daily Coffee                           │
│  $5.00 · Daily                          │
│  Next: Tomorrow                         │
├─────────────────────────────────────────┤
│                                         │
│  ─── Inactive ───                       │
│                                         │
│  Old Subscription (deleted)             │
│  Was: $9.99 · Monthly                   │
└─────────────────────────────────────────┘
```

### Posting a Virtual Instance

1. User taps **Post** on a virtual instance
2. Transaction form opens, pre-filled with:
   - All values from the recurring template (description, amount, currency, type)
   - Date defaulting to the **intended occurrence date** (user can change)
   - Category, tags from template
   - Location from **user's current location** (not from template)
3. User can modify any field before saving
4. On save:
   - Real transaction is created with `recurringTransactionID` set
   - `postedCount` increments on the recurring template
   - `nextDueDate` advances to next occurrence
   - If end condition is met, status changes to `completed`

### Skipping an Instance

1. User taps **Skip** on a virtual instance
2. Confirmation (optional): "Skip this occurrence?"
3. `nextDueDate` advances to next occurrence
4. No transaction is created
5. (Optional) Track skip count for analytics

---

## Edge Cases

### User hasn't opened app in several days (daily recurring)

- **Behavior**: Show one virtual instance with indicator "(X due)"
- **Example**: "Daily Coffee (5 due)" — means 5 occurrences are overdue
- **Post**: Creates one transaction, advances to next occurrence, count decreases
- **Skip**: Advances to next occurrence, count decreases
- User can post/skip repeatedly to catch up, or skip all at once

### Recurring set for 1st of month, user pays on 2nd

- Virtual instance appears on the 1st (intended date = Jan 1)
- User posts on the 2nd
- Transaction form shows Jan 1 as default date
- User changes date to Jan 2 (their actual payment date)
- After save: `nextDueDate` advances to Feb 1
- ✅ No duplicate virtual instance

### Delete a recurring template

- Template status set to `deleted` (soft delete)
- No more virtual instances shown
- Existing posted transactions keep their `recurringTransactionID` link
- User can still view the template from transaction detail
- Template appears in "Inactive" section of Recurring tab

### End condition: after N occurrences

- Track `postedCount` on template
- When `postedCount >= endAfterOccurrences`, set status to `completed`
- Show in "Inactive" section with "Completed" badge

### End condition: on specific date

- When `nextDueDate > endDate`, set status to `completed`
- No more virtual instances shown

### Pause a recurring template

- User can pause without deleting
- Status set to `paused`
- No virtual instances shown while paused
- `nextDueDate` is NOT advanced (resumes from where it left off)
- Show in "Inactive" section with "Paused" badge and option to resume

---

## Computing Virtual Instances

Virtual instances are computed at runtime, not stored.

```swift
func virtualInstances(for template: RecurringTransaction, asOf today: Date) -> [VirtualInstance] {
    guard template.status == .active else { return [] }
    guard template.nextDueDate <= today else { return [] }

    // Count how many occurrences are due
    var dueCount = 0
    var checkDate = template.nextDueDate
    while checkDate <= today {
        dueCount += 1
        checkDate = nextOccurrence(after: checkDate, rule: template.recurrenceRule)

        // Check end conditions
        if let endDate = template.endDate, checkDate > endDate { break }
        if let maxCount = template.endAfterOccurrences,
           template.postedCount + dueCount >= maxCount { break }
    }

    return [VirtualInstance(
        recurringTransaction: template,
        intendedDate: template.nextDueDate,
        dueCount: dueCount
    )]
}
```

---

## Next Occurrence Calculation

The recurrence rule determines when the next occurrence happens.

```swift
func nextOccurrence(after date: Date, rule: RecurrenceRule) -> Date {
    switch rule.frequency {
    case .daily:
        return calendar.date(byAdding: .day, value: rule.interval, to: date)

    case .weekly:
        if rule.weeklyDays.isEmpty {
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: date)
        } else {
            // Find next selected weekday
            // ... (more complex logic)
        }

    case .monthly:
        switch rule.monthlyMode {
        case .each:
            // Next month on same/selected day(s)
        case .onThe:
            // Next month on Nth weekday
        }

    case .yearly:
        // Next year on same date, or in selected months on Nth weekday
    }
}
```

---

## Implementation Plan

### Phase 1: Database Schema & Models ✅
- [x] Create `RecurringTransaction` model with `@Table` macro
- [x] Create `RecurringTransactionCategory` model
- [x] Create `RecurringTransactionTag` model
- [x] Create migration: `recurringTransactions` table
- [x] Create migration: `recurringTransactionsCategories` table
- [x] Create migration: `recurringTransactionsTags` table
- [x] Create migration: add `recurringTransactionID` to `transactions`
- [x] Create indexes for foreign keys
- [x] Recurrence rule stored as flattened columns (frequency, interval, weeklyDays, etc.)

### Phase 2: Recurring Tab — List of Templates
- [ ] Create `RecurringTransactionsList` reducer
- [ ] Create `RecurringTransactionsListView`
- [ ] Query and display all recurring transactions grouped by status
- [ ] Display: description, amount, frequency summary, next due date
- [ ] Add button to create new recurring transaction
- [ ] Wire into App.swift (replace RecurrencePicker playground)

### Phase 3: Recurring Transaction Form
- [ ] Create `RecurringTransactionForm` reducer
- [ ] Create `RecurringTransactionFormView`
- [ ] Include all transaction fields (amount, description, currency, type)
- [ ] Include RecurrencePicker (already built!)
- [ ] Include category picker
- [ ] Include tags picker
- [ ] Handle create operation
- [ ] Handle edit operation
- [ ] Handle delete (soft delete → set status to deleted)
- [ ] Handle pause/resume

Note: No location picker — location is captured from current location when posting.

### Phase 4: Virtual Instances in Transactions List
- [ ] Create `VirtualInstance` model (non-persisted)
- [ ] Create function to compute virtual instances from active templates
- [ ] Modify `TransactionsList` state to include virtual instances
- [ ] Create "Due" section UI at top of transactions list
- [ ] Show due count when multiple occurrences are overdue
- [ ] Implement "Post" action → opens transaction form pre-filled
- [ ] Implement "Skip" action → advances `nextDueDate`
- [ ] Update `nextDueDate` after post/skip

### Phase 5: Transaction Form Integration
- [ ] Pre-fill transaction form from virtual instance
- [ ] Set `recurringTransactionID` when saving posted transaction
- [ ] Increment `postedCount` on recurring template
- [ ] Check and handle end conditions after posting

### Phase 6: Polish & Linking
- [ ] Show recurring symbol (🔄) on posted transactions in list
- [ ] Tapping posted transaction shows "View recurring template" option
- [ ] Navigate to recurring template detail from transaction
- [ ] Handle end conditions (auto-complete when limit reached)
- [ ] Add "Skip All" option for catching up quickly

### Phase 7: Next Occurrence Logic
- [ ] Implement `nextOccurrence(after:rule:)` for daily
- [ ] Implement `nextOccurrence(after:rule:)` for weekly (with weekday selection)
- [ ] Implement `nextOccurrence(after:rule:)` for monthly (each mode)
- [ ] Implement `nextOccurrence(after:rule:)` for monthly (onThe mode)
- [ ] Implement `nextOccurrence(after:rule:)` for yearly
- [ ] Handle interval (every N days/weeks/months/years)
- [ ] Write unit tests for next occurrence logic

---

## Future Enhancements (Not in Initial Scope)

- [ ] Notifications/reminders for due recurring transactions
- [ ] "Edit all future instances" vs "edit just this occurrence"
- [ ] Recurring transaction analytics (total spent over time)
- [ ] Import/export recurring transactions
- [ ] Suggested recurring transactions based on transaction history
