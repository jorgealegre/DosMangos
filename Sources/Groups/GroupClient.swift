import CloudKit
import Dependencies
import DependenciesMacros
import Foundation
import SQLiteData

enum GroupClientError: LocalizedError {
    case groupNotFound
    case iCloudAuthenticationRequired
    case sharingPermissionDenied
    case sharingFailed(String)

    var errorDescription: String? {
        switch self {
        case .groupNotFound:
            return "Group not found."
        case .iCloudAuthenticationRequired:
            return "Could not share because iCloud needs authentication. Open Settings on the simulator/device, sign in or re-enter your Apple Account password, and try again."
        case .sharingPermissionDenied:
            return "Could not share this group due to iCloud permissions. Check your iCloud account and sharing permissions, then try again."
        case let .sharingFailed(message):
            return "Could not share this group. \(message)"
        }
    }
}

struct GroupTransactionSplitInput: Equatable, Sendable {
    var memberID: GroupMember.ID
    var paidAmountMinorUnits: Int
    var owedAmountMinorUnits: Int
    var owedPercentage: Double?
}

struct GroupTransactionInput: Equatable, Sendable {
    var groupID: TransactionGroup.ID
    var description: String
    var valueMinorUnits: Int
    var currencyCode: String
    var type: GroupTransactionType
    var splitType: GroupSplitType
    var date: Date
    var splits: [GroupTransactionSplitInput]
    var location: GroupLocationInput?
}

struct GroupLocationInput: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var city: String?
    var countryCode: String?
}

enum GroupTransactionValidationError: LocalizedError {
    case noSplits
    case paidTotalMismatch
    case owedTotalMismatch
    case percentageSplitInvalid
    case transferMustHaveTwoMembers
    case transferShapeInvalid

    var errorDescription: String? {
        switch self {
        case .noSplits:
            return "A group transaction must include at least one split."
        case .paidTotalMismatch:
            return "The total paid amount must match the transaction total."
        case .owedTotalMismatch:
            return "The total owed amount must match the transaction total."
        case .percentageSplitInvalid:
            return "For percentage splits, percentages must add up to 100."
        case .transferMustHaveTwoMembers:
            return "Transfers must involve exactly two members."
        case .transferShapeInvalid:
            return "Transfer splits must be one payer and one receiver for the full amount."
        }
    }
}

@DependencyClient
struct GroupClient {
    var createGroup: @Sendable (
        _ name: String,
        _ description: String,
        _ defaultCurrencyCode: String,
        _ creatorName: String
    ) async throws -> TransactionGroup.ID

    var shareGroup: @Sendable (
        _ groupID: TransactionGroup.ID
    ) async throws -> SharedRecord

    var claimMember: @Sendable (
        _ memberID: GroupMember.ID
    ) async throws -> Bool

    var ensureParticipantID: @Sendable () async throws -> Void

    var deleteGroup: @Sendable (
        _ groupID: TransactionGroup.ID
    ) async throws -> Void

    var createGroupTransaction: @Sendable (
        _ input: GroupTransactionInput
    ) async throws -> GroupTransaction.ID
}

extension GroupClient: DependencyKey {
    static let liveValue: Self = {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.defaultSyncEngine) var syncEngine
        @Dependency(\.exchangeRate) var exchangeRate
        @Dependency(\.date.now) var now
        @Dependency(\.uuid) var uuid

        @Sendable func currentUserParticipantID() async throws -> String {
            let recordID = try await CKContainer.default().userRecordID()
            return recordID.recordName
        }

        @Sendable func mapShareError(_ error: Error) -> GroupClientError {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .notAuthenticated, .accountTemporarilyUnavailable:
                    return .iCloudAuthenticationRequired
                case .permissionFailure:
                    return .sharingPermissionDenied
                default:
                    return .sharingFailed(ckError.localizedDescription)
                }
            }
            return .sharingFailed(error.localizedDescription)
        }

        @Sendable func upsertCurrentUserParticipantIDLocalSetting(_ participantID: String) async throws {
            try await database.write { db in
                try #sql("""
                INSERT INTO "local_settings" ("key", "value")
                VALUES ('currentUserParticipantID', \(bind: participantID))
                ON CONFLICT("key") DO UPDATE SET
                    "value" = excluded."value"
                """).execute(db)
            }
        }

        @Sendable func validateTransactionInput(_ input: GroupTransactionInput) throws {
            guard !input.splits.isEmpty else {
                throw GroupTransactionValidationError.noSplits
            }

            let paidTotal = input.splits.reduce(0) { $0 + $1.paidAmountMinorUnits }
            guard paidTotal == input.valueMinorUnits else {
                throw GroupTransactionValidationError.paidTotalMismatch
            }

            let owedTotal = input.splits.reduce(0) { $0 + $1.owedAmountMinorUnits }
            guard owedTotal == input.valueMinorUnits else {
                throw GroupTransactionValidationError.owedTotalMismatch
            }

            if input.splitType == .percentage {
                let percentageTotal = input.splits.reduce(0.0) { $0 + ($1.owedPercentage ?? 0.0) }
                if abs(percentageTotal - 100.0) > 0.0001 {
                    throw GroupTransactionValidationError.percentageSplitInvalid
                }
            }

            if input.type == .transfer {
                guard input.splits.count == 2 else {
                    throw GroupTransactionValidationError.transferMustHaveTwoMembers
                }

                let validShape = input.splits.contains {
                    $0.paidAmountMinorUnits == input.valueMinorUnits && $0.owedAmountMinorUnits == 0
                } && input.splits.contains {
                    $0.paidAmountMinorUnits == 0 && $0.owedAmountMinorUnits == input.valueMinorUnits
                }
                guard validShape else {
                    throw GroupTransactionValidationError.transferShapeInvalid
                }
            }
        }

        @Sendable func createOrUpdateLocalMirror(
            groupTransaction: GroupTransaction,
            split: GroupTransactionSplit,
            location: GroupTransactionLocation?
        ) async throws {
            let defaultCurrency = try await database.read { db in
                try UserSettings
                    .all
                    .select(\.defaultCurrency)
                    .fetchOne(db)
            } ?? "USD"

            let convertedValueMinorUnits: Int?
            let convertedCurrencyCode: String?
            if groupTransaction.currencyCode == defaultCurrency {
                convertedValueMinorUnits = split.owedAmountMinorUnits
                convertedCurrencyCode = defaultCurrency
            } else {
                do {
                    let rate = try await exchangeRate.getRate(
                        groupTransaction.currencyCode,
                        defaultCurrency,
                        groupTransaction.localDate
                    )
                    convertedValueMinorUnits = Int(Double(split.owedAmountMinorUnits) * rate)
                    convertedCurrencyCode = defaultCurrency
                } catch {
                    convertedValueMinorUnits = nil
                    convertedCurrencyCode = nil
                }
            }

            try await database.write { db in
                try Transaction.upsert {
                    Transaction.Draft(
                        id: split.id,
                        description: groupTransaction.description,
                        valueMinorUnits: split.owedAmountMinorUnits,
                        currencyCode: groupTransaction.currencyCode,
                        convertedValueMinorUnits: convertedValueMinorUnits,
                        convertedCurrencyCode: convertedCurrencyCode,
                        type: .expense,
                        createdAtUTC: groupTransaction.createdAtUTC,
                        localYear: groupTransaction.localYear,
                        localMonth: groupTransaction.localMonth,
                        localDay: groupTransaction.localDay,
                        recurringTransactionID: nil,
                        groupTransactionSplitID: split.id
                    )
                }.execute(db)

                guard let location else { return }
                try TransactionLocation.upsert {
                    TransactionLocation.Draft(
                        transactionID: split.id,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        city: location.city,
                        countryCode: location.countryCode
                    )
                }.execute(db)
            }
        }

        return Self(
            createGroup: { name, description, defaultCurrencyCode, creatorName in
                let participantID = try? await currentUserParticipantID()

                return try await database.write { db in
                    let groupID = uuid()

                    try TransactionGroup.insert {
                        TransactionGroup.Draft(
                            id: groupID,
                            name: name,
                            description: description,
                            defaultCurrencyCode: defaultCurrencyCode,
                            simplifyDebts: true,
                            createdAtUTC: now
                        )
                    }.execute(db)

                    try GroupMember.insert {
                        GroupMember.Draft(
                            groupID: groupID,
                            name: creatorName,
                            cloudKitParticipantID: participantID
                        )
                    }.execute(db)

                    return groupID
                }
            },
            shareGroup: { groupID in
                let group = try await database.read { db in
                    try TransactionGroup.find(groupID).fetchOne(db)
                }
                guard let group else {
                    throw GroupClientError.groupNotFound
                }

                do {
                    return try await syncEngine.share(record: group) { share in
                        share[CKShare.SystemFieldKey.title] = group.name
                    }
                } catch {
                    throw mapShareError(error)
                }
            },
            claimMember: { memberID in
                let participantID = try await currentUserParticipantID()

                let didClaim = try await database.write { db in
                    try #sql("""
                    UPDATE "group_members" AS target
                    SET "cloudKitParticipantID" = \(bind: participantID)
                    WHERE target."id" = \(bind: memberID)
                      AND target."cloudKitParticipantID" IS NULL
                      AND NOT EXISTS (
                        SELECT 1
                        FROM "group_members" AS existing
                        WHERE existing."groupID" = target."groupID"
                          AND existing."cloudKitParticipantID" = \(bind: participantID)
                      )
                    """).execute(db)

                    let claimedBy = try GroupMember
                        .find(memberID)
                        .select(\.cloudKitParticipantID)
                        .fetchOne(db)
                    return claimedBy == participantID
                }

                if didClaim {
                    let splits = try await database.read { db in
                        try GroupTransactionSplit
                            .where { $0.memberID.eq(memberID) }
                            .fetchAll(db)
                    }

                    for split in splits {
                        let (transaction, location) = try await database.read { db in
                            let transaction = try GroupTransaction
                                .find(split.groupTransactionID)
                                .fetchOne(db)
                            let location = try GroupTransactionLocation
                                .find(split.groupTransactionID)
                                .fetchOne(db)
                            return (transaction, location)
                        }

                        guard let transaction else { continue }
                        try? await createOrUpdateLocalMirror(
                            groupTransaction: transaction,
                            split: split,
                            location: location
                        )
                    }
                }

                return didClaim
            },
            ensureParticipantID: {
                let participantID = try await currentUserParticipantID()
                try await upsertCurrentUserParticipantIDLocalSetting(participantID)
            },
            deleteGroup: { groupID in
                try await database.write { db in
                    try TransactionGroup
                        .where { $0.id.eq(groupID) }
                        .delete()
                        .execute(db)
                }
            },
            createGroupTransaction: { input in
                try validateTransactionInput(input)

                let local = input.date.localDateComponents()
                let groupCurrency = try await database.read { db in
                    try TransactionGroup
                        .find(input.groupID)
                        .select(\.defaultCurrencyCode)
                        .fetchOne(db)
                }

                let convertedValueMinorUnits: Int?
                let convertedCurrencyCode: String?
                if let groupCurrency, input.currencyCode != groupCurrency {
                    do {
                        let rate = try await exchangeRate.getRate(input.currencyCode, groupCurrency, input.date)
                        convertedValueMinorUnits = Int(Double(input.valueMinorUnits) * rate)
                        convertedCurrencyCode = groupCurrency
                    } catch {
                        convertedValueMinorUnits = nil
                        convertedCurrencyCode = nil
                    }
                } else if let groupCurrency {
                    convertedValueMinorUnits = input.valueMinorUnits
                    convertedCurrencyCode = groupCurrency
                } else {
                    convertedValueMinorUnits = nil
                    convertedCurrencyCode = nil
                }

                let transactionID = uuid()
                let splitRows: [(id: UUID, split: GroupTransactionSplitInput)] = input.splits.map {
                    (uuid(), $0)
                }
                try await database.write { db in
                    try GroupTransaction.insert {
                        GroupTransaction.Draft(
                            id: transactionID,
                            groupID: input.groupID,
                            description: input.description,
                            valueMinorUnits: input.valueMinorUnits,
                            currencyCode: input.currencyCode,
                            convertedValueMinorUnits: convertedValueMinorUnits,
                            convertedCurrencyCode: convertedCurrencyCode,
                            type: input.type,
                            splitType: input.splitType,
                            createdAtUTC: input.date,
                            localYear: local.year,
                            localMonth: local.month,
                            localDay: local.day
                        )
                    }.execute(db)

                    for splitRow in splitRows {
                        try GroupTransactionSplit.insert {
                            GroupTransactionSplit.Draft(
                                id: splitRow.id,
                                groupTransactionID: transactionID,
                                memberID: splitRow.split.memberID,
                                paidAmountMinorUnits: splitRow.split.paidAmountMinorUnits,
                                owedAmountMinorUnits: splitRow.split.owedAmountMinorUnits,
                                owedPercentage: splitRow.split.owedPercentage
                            )
                        }.execute(db)
                    }

                    if let location = input.location {
                        try GroupTransactionLocation.upsert {
                            GroupTransactionLocation.Draft(
                                groupTransactionID: transactionID,
                                latitude: location.latitude,
                                longitude: location.longitude,
                                city: location.city,
                                countryCode: location.countryCode
                            )
                        }.execute(db)
                    }
                }

                let participantID = try? await currentUserParticipantID()
                if let participantID {
                    let memberByID = try await database.read { db in
                        try GroupMember
                            .where { $0.groupID.eq(input.groupID) }
                            .fetchAll(db)
                    }
                    .reduce(into: [GroupMember.ID: GroupMember]()) { map, member in
                        map[member.id] = member
                    }

                    if let mySplitRow = splitRows.first(where: { splitRow in
                        let split = splitRow.split
                        return memberByID[split.memberID]?.cloudKitParticipantID == participantID
                    }) {
                        let tx = GroupTransaction(
                            id: transactionID,
                            groupID: input.groupID,
                            description: input.description,
                            valueMinorUnits: input.valueMinorUnits,
                            currencyCode: input.currencyCode,
                            convertedValueMinorUnits: convertedValueMinorUnits,
                            convertedCurrencyCode: convertedCurrencyCode,
                            type: input.type,
                            splitType: input.splitType,
                            createdAtUTC: input.date,
                            localYear: local.year,
                            localMonth: local.month,
                            localDay: local.day
                        )
                        let split = GroupTransactionSplit(
                            id: mySplitRow.id,
                            groupTransactionID: transactionID,
                            memberID: mySplitRow.split.memberID,
                            paidAmountMinorUnits: mySplitRow.split.paidAmountMinorUnits,
                            owedAmountMinorUnits: mySplitRow.split.owedAmountMinorUnits,
                            owedPercentage: mySplitRow.split.owedPercentage
                        )
                        let location = input.location.map { loc in
                            GroupTransactionLocation(
                                groupTransactionID: transactionID,
                                latitude: loc.latitude,
                                longitude: loc.longitude,
                                city: loc.city,
                                countryCode: loc.countryCode
                            )
                        }
                        try await createOrUpdateLocalMirror(
                            groupTransaction: tx,
                            split: split,
                            location: location
                        )
                    }
                }

                return transactionID
            }
        )
    }()
}

extension GroupClient: TestDependencyKey {
    static let testValue = Self()
}

extension DependencyValues {
    var groupClient: GroupClient {
        get { self[GroupClient.self] }
        set { self[GroupClient.self] = newValue }
    }
}
