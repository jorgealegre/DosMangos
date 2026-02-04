import Foundation
import SQLiteData

extension DatabaseMigrator {
    mutating func registerAllMigrations() {
        self.registerMigration("Create initial tables") { db in
            try #sql(
            """
            CREATE TABLE "transactions" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "description" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
              "valueMinorUnits" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "currencyCode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
              "type" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
              "localYear" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "localMonth" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "localDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "locationID" TEXT REFERENCES "transaction_locations"("id") ON DELETE SET NULL
            ) STRICT
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE TABLE "transaction_locations" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "latitude" REAL NOT NULL,
              "longitude" REAL NOT NULL,
              "city" TEXT,
              "countryCode" TEXT
            ) STRICT
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE TABLE "categories" (
              "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL,
              "parentCategoryID" TEXT REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE TABLE "transactionsCategories" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
              "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE,
              UNIQUE("transactionID", "categoryID") ON CONFLICT IGNORE
            ) STRICT
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE TABLE "tags" (
              "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL
            ) STRICT
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE TABLE "transactionsTags" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
              "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE,
              UNIQUE("transactionID", "tagID") ON CONFLICT IGNORE
            ) STRICT
            """
            )
            .execute(db)
        }

        self.registerMigration("Create foreign key indexes") { db in
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactions_localYMD_createdAtUTC"
            ON "transactions"("localYear", "localMonth", "localDay", "createdAtUTC")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_transactionID"
            ON "transactionsCategories"("transactionID")
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_categoryID"
            ON "transactionsCategories"("categoryID")
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactionsTags_transactionID"
            ON "transactionsTags"("transactionID")
            """
            )
            .execute(db)
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactionsTags_tagID"
            ON "transactionsTags"("tagID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_categories_parentCategoryID"
            ON "categories"("parentCategoryID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactions_locationID"
            ON "transactions"("locationID")
            """
            )
            .execute(db)
        }

        self.registerMigration("Add currency conversion support") { db in
            // Add conversion columns as NULLABLE
            // NULL = conversion not yet available (offline, rate not found, etc.)
            try #sql(
            """
            ALTER TABLE "transactions"
            ADD COLUMN "convertedValueMinorUnits" INTEGER
            """
            )
            .execute(db)

            try #sql(
            """
            ALTER TABLE "transactions"
            ADD COLUMN "convertedCurrencyCode" TEXT
            """
            )
            .execute(db)

            // Create exchangeRates table for caching
            try #sql(
            """
            CREATE TABLE "exchangeRates" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "fromCurrency" TEXT NOT NULL,
              "toCurrency" TEXT NOT NULL,
              "rate" REAL NOT NULL,
              "date" TEXT NOT NULL,
              "fetchedAt" TEXT NOT NULL DEFAULT (datetime('now')),
              UNIQUE("fromCurrency", "toCurrency", "date") ON CONFLICT REPLACE
            ) STRICT
            """
            )
            .execute(db)

            // Index for fast rate lookups
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_exchangeRates_lookup"
            ON "exchangeRates"("fromCurrency", "toCurrency", "date")
            """
            )
            .execute(db)

            // Backfill existing USD transactions (same currency, no conversion needed)
            try #sql(
            """
            UPDATE "transactions"
            SET "convertedValueMinorUnits" = "valueMinorUnits",
                "convertedCurrencyCode" = "currencyCode"
            WHERE "currencyCode" = 'USD'
            """
            )
            .execute(db)

            // Non-USD transactions remain NULL (we don't know historical rates)
        }

        self.registerMigration("Add recurring transactions support") { db in
            // Create recurringTransactions table
            try #sql(
            """
            CREATE TABLE "recurringTransactions" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "description" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
              "valueMinorUnits" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "currencyCode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'USD',
              "type" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,

              -- Recurrence Rule (flattened)
              "frequency" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "interval" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1,
              "weeklyDays" TEXT,
              "monthlyMode" INTEGER,
              "monthlyDays" TEXT,
              "monthlyOrdinal" INTEGER,
              "monthlyWeekday" INTEGER,
              "yearlyMonths" TEXT,
              "yearlyDaysOfWeekEnabled" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "yearlyOrdinal" INTEGER,
              "yearlyWeekday" INTEGER,
              "endMode" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "endDate" TEXT,
              "endAfterOccurrences" INTEGER,

              -- State (local date components, no time)
              "startLocalYear" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "startLocalMonth" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "startLocalDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "nextDueLocalYear" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "nextDueLocalMonth" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "nextDueLocalDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "postedCount" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "status" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,

              -- Metadata
              "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
              "updatedAtUTC" TEXT NOT NULL DEFAULT (datetime('now'))
            ) STRICT
            """
            )
            .execute(db)

            // Create recurringTransactionsCategories join table
            try #sql(
            """
            CREATE TABLE "recurringTransactionsCategories" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
              "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE,
              UNIQUE("recurringTransactionID", "categoryID") ON CONFLICT IGNORE
            ) STRICT
            """
            )
            .execute(db)

            // Create recurringTransactionsTags join table
            try #sql(
            """
            CREATE TABLE "recurringTransactionsTags" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
              "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE,
              UNIQUE("recurringTransactionID", "tagID") ON CONFLICT IGNORE
            ) STRICT
            """
            )
            .execute(db)

            // Add recurringTransactionID to transactions table
            try #sql(
            """
            ALTER TABLE "transactions"
            ADD COLUMN "recurringTransactionID" TEXT REFERENCES "recurringTransactions"("id") ON DELETE SET NULL
            """
            )
            .execute(db)

            // Create indexes for foreign keys
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_recurringTransactionID"
            ON "recurringTransactionsCategories"("recurringTransactionID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_categoryID"
            ON "recurringTransactionsCategories"("categoryID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_recurringTransactionID"
            ON "recurringTransactionsTags"("recurringTransactionID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_tagID"
            ON "recurringTransactionsTags"("tagID")
            """
            )
            .execute(db)

            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_transactions_recurringTransactionID"
            ON "transactions"("recurringTransactionID")
            """
            )
            .execute(db)

            // Index for querying active recurring transactions by next due date
            try #sql(
            """
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactions_status_nextDue"
            ON "recurringTransactions"("status", "nextDueLocalYear", "nextDueLocalMonth", "nextDueLocalDay")
            """
            )
            .execute(db)
        }

        self.registerMigration("Shared PK for transaction_locations") { db in
            // Switching from: transactions.locationID -> transaction_locations.id
            // To: transaction_locations.transactionID -> transactions.id (shared PK pattern)

            // 1. Create new transaction_locations with transactionID as PK
            try #sql("""
            CREATE TABLE "transaction_locations_new" (
              "transactionID" TEXT PRIMARY KEY NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
              "latitude" REAL NOT NULL,
              "longitude" REAL NOT NULL,
              "city" TEXT,
              "countryCode" TEXT
            ) STRICT
            """).execute(db)

            // 2. Copy data, mapping old location IDs to their transaction IDs
            try #sql("""
            INSERT INTO "transaction_locations_new" ("transactionID", "latitude", "longitude", "city", "countryCode")
            SELECT t."id", tl."latitude", tl."longitude", tl."city", tl."countryCode"
            FROM "transaction_locations" tl
            JOIN "transactions" t ON t."locationID" = tl."id"
            """).execute(db)

            // 3. Drop old table and rename new
            try #sql("""
            DROP TABLE "transaction_locations"
            """).execute(db)
            try #sql("""
            ALTER TABLE "transaction_locations_new" RENAME TO "transaction_locations"
            """).execute(db)

            // 4. Recreate transactions table without locationID column
            try #sql("""
            CREATE TABLE "transactions_new" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "description" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
              "valueMinorUnits" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "currencyCode" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
              "type" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "createdAtUTC" TEXT NOT NULL DEFAULT (datetime('now')),
              "localYear" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "localMonth" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "localDay" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
              "convertedValueMinorUnits" INTEGER,
              "convertedCurrencyCode" TEXT,
              "recurringTransactionID" TEXT REFERENCES "recurringTransactions"("id") ON DELETE SET NULL
            ) STRICT
            """).execute(db)

            // 5. Copy data (excluding locationID)
            try #sql("""
            INSERT INTO "transactions_new"
            ("id", "description", "valueMinorUnits", "currencyCode", "type", "createdAtUTC",
             "localYear", "localMonth", "localDay", "convertedValueMinorUnits",
             "convertedCurrencyCode", "recurringTransactionID")
            SELECT "id", "description", "valueMinorUnits", "currencyCode", "type", "createdAtUTC",
                   "localYear", "localMonth", "localDay", "convertedValueMinorUnits",
                   "convertedCurrencyCode", "recurringTransactionID"
            FROM "transactions"
            """).execute(db)

            // 6. Drop old table and rename new
            try #sql("""
            DROP TABLE "transactions"
            """).execute(db)
            try #sql("""
            ALTER TABLE "transactions_new" RENAME TO "transactions"
            """).execute(db)

            // 7. Recreate indexes on transactions (excluding idx_transactions_locationID)
            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactions_localYMD_createdAtUTC"
            ON "transactions"("localYear", "localMonth", "localDay", "createdAtUTC")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactions_recurringTransactionID"
            ON "transactions"("recurringTransactionID")
            """).execute(db)
        }

        self.registerMigration("Split categories into categories and subcategories") { db in
            // =================================================================
            // STEP 1: Save existing data to temp tables
            // =================================================================

            // Save parent/standalone categories (those without a parent)
            try #sql("""
            CREATE TEMPORARY TABLE "temp_parent_categories" AS
            SELECT "title"
            FROM "categories"
            WHERE "parentCategoryID" IS NULL
            """).execute(db)

            // Save child categories with their parent reference
            try #sql("""
            CREATE TEMPORARY TABLE "temp_child_categories" AS
            SELECT "title", "parentCategoryID"
            FROM "categories"
            WHERE "parentCategoryID" IS NOT NULL
            """).execute(db)

            // Save transactionsCategories with info about whether it references a parent or child
            try #sql("""
            CREATE TEMPORARY TABLE "temp_transactionsCategories" AS
            SELECT
                tc."id",
                tc."transactionID",
                tc."categoryID",
                CASE WHEN c."parentCategoryID" IS NULL THEN 1 ELSE 0 END AS "isParent"
            FROM "transactionsCategories" tc
            JOIN "categories" c ON tc."categoryID" = c."title"
            """).execute(db)

            // Save recurringTransactionsCategories similarly
            try #sql("""
            CREATE TEMPORARY TABLE "temp_recurringTransactionsCategories" AS
            SELECT
                rtc."id",
                rtc."recurringTransactionID",
                rtc."categoryID",
                CASE WHEN c."parentCategoryID" IS NULL THEN 1 ELSE 0 END AS "isParent"
            FROM "recurringTransactionsCategories" rtc
            JOIN "categories" c ON rtc."categoryID" = c."title"
            """).execute(db)

            // =================================================================
            // STEP 2: Drop old tables (order matters for FK constraints)
            // =================================================================

            try #sql("""
            DROP TABLE "transactionsCategories"
            """).execute(db)

            try #sql("""
            DROP TABLE "recurringTransactionsCategories"
            """).execute(db)

            try #sql("""
            DROP TABLE "categories"
            """).execute(db)

            // =================================================================
            // STEP 3: Create new table structure
            // =================================================================

            // New categories table (grouping containers, title as PK)
            try #sql("""
            CREATE TABLE "categories" (
                "title" TEXT COLLATE NOCASE PRIMARY KEY NOT NULL
            ) STRICT
            """).execute(db)

            // New subcategories table (UUID PK, references categories)
            // Subcategories are the only assignable items to transactions
            try #sql("""
            CREATE TABLE "subcategories" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT COLLATE NOCASE NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "categoryID" TEXT NOT NULL REFERENCES "categories"("title") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """).execute(db)

            // New transactionsCategories - only subcategoryID (required)
            try #sql("""
            CREATE TABLE "transactionsCategories" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
                "subcategoryID" TEXT NOT NULL REFERENCES "subcategories"("id") ON DELETE CASCADE
            ) STRICT
            """).execute(db)

            // New recurringTransactionsCategories - only subcategoryID (required)
            try #sql("""
            CREATE TABLE "recurringTransactionsCategories" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
                "subcategoryID" TEXT NOT NULL REFERENCES "subcategories"("id") ON DELETE CASCADE
            ) STRICT
            """).execute(db)

            // =================================================================
            // STEP 4: Restore data from temp tables
            // =================================================================

            // Insert parent/standalone categories
            try #sql("""
            INSERT INTO "categories" ("title")
            SELECT "title" FROM "temp_parent_categories"
            """).execute(db)

            // Insert child categories as subcategories (generates new UUIDs via default)
            try #sql("""
            INSERT INTO "subcategories" ("title", "categoryID")
            SELECT "title", "parentCategoryID"
            FROM "temp_child_categories"
            """).execute(db)

            // Create "Other" subcategories for parent categories that have transactions assigned
            // but no existing subcategories to migrate to
            try #sql("""
            INSERT INTO "subcategories" ("title", "categoryID")
            SELECT DISTINCT 'Other', ttc."categoryID"
            FROM "temp_transactionsCategories" ttc
            WHERE ttc."isParent" = 1
            """).execute(db)

            // Also for recurring transactions
            try #sql("""
            INSERT OR IGNORE INTO "subcategories" ("title", "categoryID")
            SELECT DISTINCT 'Other', trtc."categoryID"
            FROM "temp_recurringTransactionsCategories" trtc
            WHERE trtc."isParent" = 1
            """).execute(db)

            // Restore transactionsCategories - subcategory references (child categories)
            try #sql("""
            INSERT INTO "transactionsCategories" ("id", "transactionID", "subcategoryID")
            SELECT ttc."id", ttc."transactionID", s."id"
            FROM "temp_transactionsCategories" ttc
            JOIN "temp_child_categories" tcc ON ttc."categoryID" = tcc."title"
            JOIN "subcategories" s ON s."title" = tcc."title" AND s."categoryID" = tcc."parentCategoryID"
            WHERE ttc."isParent" = 0
            """).execute(db)

            // Restore transactionsCategories - parent category refs → link to "Other" subcategory
            try #sql("""
            INSERT INTO "transactionsCategories" ("id", "transactionID", "subcategoryID")
            SELECT ttc."id", ttc."transactionID", s."id"
            FROM "temp_transactionsCategories" ttc
            JOIN "subcategories" s ON s."title" = 'Other' AND s."categoryID" = ttc."categoryID"
            WHERE ttc."isParent" = 1
            """).execute(db)

            // Restore recurringTransactionsCategories - subcategory references (child categories)
            try #sql("""
            INSERT INTO "recurringTransactionsCategories" ("id", "recurringTransactionID", "subcategoryID")
            SELECT trtc."id", trtc."recurringTransactionID", s."id"
            FROM "temp_recurringTransactionsCategories" trtc
            JOIN "temp_child_categories" tcc ON trtc."categoryID" = tcc."title"
            JOIN "subcategories" s ON s."title" = tcc."title" AND s."categoryID" = tcc."parentCategoryID"
            WHERE trtc."isParent" = 0
            """).execute(db)

            // Restore recurringTransactionsCategories - parent category refs → link to "Other" subcategory
            try #sql("""
            INSERT INTO "recurringTransactionsCategories" ("id", "recurringTransactionID", "subcategoryID")
            SELECT trtc."id", trtc."recurringTransactionID", s."id"
            FROM "temp_recurringTransactionsCategories" trtc
            JOIN "subcategories" s ON s."title" = 'Other' AND s."categoryID" = trtc."categoryID"
            WHERE trtc."isParent" = 1
            """).execute(db)

            // =================================================================
            // STEP 5: Drop temp tables
            // =================================================================

            try #sql("""
            DROP TABLE "temp_parent_categories"
            """).execute(db)

            try #sql("""
            DROP TABLE "temp_child_categories"
            """).execute(db)

            try #sql("""
            DROP TABLE "temp_transactionsCategories"
            """).execute(db)

            try #sql("""
            DROP TABLE "temp_recurringTransactionsCategories"
            """).execute(db)

            // =================================================================
            // STEP 6: Create indexes
            // =================================================================

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_subcategories_categoryID"
            ON "subcategories"("categoryID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_transactionID"
            ON "transactionsCategories"("transactionID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactionsCategories_subcategoryID"
            ON "transactionsCategories"("subcategoryID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_recurringTransactionID"
            ON "recurringTransactionsCategories"("recurringTransactionID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsCategories_subcategoryID"
            ON "recurringTransactionsCategories"("subcategoryID")
            """).execute(db)
        }

        self.registerMigration("Remove UNIQUE constraints for CloudKit compatibility") { db in
            // =================================================================
            // transactionsTags - Remove UNIQUE constraint
            // =================================================================

            try #sql("""
            CREATE TABLE "transactionsTags_new" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "transactionID" TEXT NOT NULL REFERENCES "transactions"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """).execute(db)

            try #sql("""
            INSERT INTO "transactionsTags_new" ("id", "transactionID", "tagID")
            SELECT "id", "transactionID", "tagID"
            FROM "transactionsTags"
            """).execute(db)

            try #sql("""
            DROP TABLE "transactionsTags"
            """).execute(db)

            try #sql("""
            ALTER TABLE "transactionsTags_new" RENAME TO "transactionsTags"
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactionsTags_transactionID"
            ON "transactionsTags"("transactionID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactionsTags_tagID"
            ON "transactionsTags"("tagID")
            """).execute(db)

            // =================================================================
            // recurringTransactionsTags - Remove UNIQUE constraint
            // =================================================================

            try #sql("""
            CREATE TABLE "recurringTransactionsTags_new" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "recurringTransactionID" TEXT NOT NULL REFERENCES "recurringTransactions"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """).execute(db)

            try #sql("""
            INSERT INTO "recurringTransactionsTags_new" ("id", "recurringTransactionID", "tagID")
            SELECT "id", "recurringTransactionID", "tagID"
            FROM "recurringTransactionsTags"
            """).execute(db)

            try #sql("""
            DROP TABLE "recurringTransactionsTags"
            """).execute(db)

            try #sql("""
            ALTER TABLE "recurringTransactionsTags_new" RENAME TO "recurringTransactionsTags"
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_recurringTransactionID"
            ON "recurringTransactionsTags"("recurringTransactionID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_recurringTransactionsTags_tagID"
            ON "recurringTransactionsTags"("tagID")
            """).execute(db)
        }

        self.registerMigration("Create userSettings table") { db in
            try #sql("""
            CREATE TABLE "userSettings" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "defaultCurrency" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'USD'
            ) STRICT
            """).execute(db)

            // Migrate from UserDefaults if a value exists, otherwise use default
            let existingCurrency = UserDefaults.standard.string(forKey: "default_currency") ?? "USD"

            try #sql("""
            INSERT INTO "userSettings" ("defaultCurrency")
            VALUES (\(bind: existingCurrency))
            """).execute(db)

            // Clean up UserDefaults
            UserDefaults.standard.removeObject(forKey: "default_currency")
        }

        self.registerMigration("Consolidate userSettings to fixed ID") { db in
            // Previous migration used random UUIDs, causing CloudKit sync to create
            // duplicate rows (one per device). Fix by consolidating to a single row
            // with a fixed ID so all devices share the same CloudKit record.

            let fixedID = "00000000-0000-0000-0000-000000000000"

            // Check if the fixed ID row already exists (e.g., synced from another device)
            let hasFixedIDRow = try #sql("""
            SELECT 1 FROM "userSettings" WHERE "id" = \(bind: fixedID)
            """, as: Int.self).fetchOne(db) != nil

            if hasFixedIDRow {
                // Fixed ID row exists (from sync), just clean up any legacy rows
                try #sql("""
                DELETE FROM "userSettings" WHERE "id" != \(bind: fixedID)
                """).execute(db)
            } else {
                // Need to consolidate: get currency, delete all, insert with fixed ID
                let existingCurrency = try #sql("""
                SELECT "defaultCurrency" FROM "userSettings" LIMIT 1
                """, as: String.self).fetchOne(db) ?? "USD"

                try #sql("""
                DELETE FROM "userSettings"
                """).execute(db)

                try #sql("""
                INSERT INTO "userSettings" ("id", "defaultCurrency")
                VALUES (\(bind: fixedID), \(bind: existingCurrency))
                """).execute(db)
            }
        }
    }
}
