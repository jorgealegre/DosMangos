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

        self.registerMigration("Rename transaction_locations.id to locationID") { db in
            // Drop the temporary view that references the column
            try #sql("DROP VIEW IF EXISTS \"transactionsListRows\"").execute(db)

            // Step 1: Rename the column in transaction_locations
            try #sql("""
            ALTER TABLE "transaction_locations" RENAME COLUMN "id" TO "locationID"
            """).execute(db)

            // Step 2: Recreate transactions table with updated FK reference
            // SQLite doesn't update FK constraint text when renaming referenced columns,
            // so we must recreate the table with the correct FK definition.
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
              "locationID" TEXT REFERENCES "transaction_locations"("locationID") ON DELETE SET NULL,
              "convertedValueMinorUnits" INTEGER,
              "convertedCurrencyCode" TEXT,
              "recurringTransactionID" TEXT REFERENCES "recurringTransactions"("id") ON DELETE SET NULL
            ) STRICT
            """).execute(db)

            // Step 3: Copy data from old table to new
            try #sql("""
            INSERT INTO "transactions_new"
            SELECT * FROM "transactions"
            """).execute(db)

            // Step 4: Drop old table and rename new one
            try #sql("DROP TABLE \"transactions\"").execute(db)
            try #sql("ALTER TABLE \"transactions_new\" RENAME TO \"transactions\"").execute(db)

            // Step 5: Recreate indexes on transactions
            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactions_localYMD_createdAtUTC"
            ON "transactions"("localYear", "localMonth", "localDay", "createdAtUTC")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactions_locationID"
            ON "transactions"("locationID")
            """).execute(db)

            try #sql("""
            CREATE INDEX IF NOT EXISTS "idx_transactions_recurringTransactionID"
            ON "transactions"("recurringTransactionID")
            """).execute(db)
        }

    }
}
