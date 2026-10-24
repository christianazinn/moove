import Foundation

// Payments and agent steps for items in rooms shared with the user (#254).
//
// The module's per-user views `my_payment` / `my_agent_event` return the user's
// own rows plus item-scoped rows (x402 comps payments, agent steps on shared
// items and listings) that another room member owns. Purchase payments never
// reach other users. `SyncSnapshot.payments` / `agentEvents` hold both, so
// anything that totals the user's own spend must use `myPayments` / `myAgentEvents`.

extension SyncSnapshot {
    /// True when the row belongs to someone else (a shared-room row). With no
    /// signed-in identity (offline fixtures) everything counts as the user's.
    public func isSharedRoom(owner: IdentityHex) -> Bool { me != nil && owner != me }

    public func isSharedRoom(_ payment: Payment) -> Bool { isSharedRoom(owner: payment.owner) }

    /// The user's own payments: what their totals and budgets are made of.
    public var myPayments: [Payment] { payments.filter { !isSharedRoom($0) } }

    /// Other members' item-scoped payments (x402 comps for shared items).
    public var roomPayments: [Payment] { payments.filter(isSharedRoom) }

    public var myAgentEvents: [AgentEvent] { agentEvents.filter { !isSharedRoom(owner: $0.owner) } }

    public var roomAgentEvents: [AgentEvent] { agentEvents.filter { isSharedRoom(owner: $0.owner) } }

    /// The Spending screen, split into the user's own log and the shared rooms' log.
    public func spendingSplit(capPerAgentUsdMicros: Int64 = UsdMicros.defaultAgentCap) -> SpendingSplit {
        SpendingSplit(
            yours: spendingLog(capPerAgentUsdMicros: capPerAgentUsdMicros),
            room: SpendingLog(payments: roomPayments, events: roomAgentEvents, capPerAgentUsdMicros: capPerAgentUsdMicros))
    }
}

/// "Yours vs room": the user's own spending log, and a separate one for what agents paid
/// on items in shared rooms. The room log is never added into the user's totals.
public struct SpendingSplit: Sendable, Equatable {
    public var yours: SpendingLog
    public var room: SpendingLog

    public var isEmpty: Bool { yours.isEmpty && room.isEmpty }

    /// Caption under the "Shared room" header.
    public static let roomCaption = "Agents paid these for items in a room you joined. They're another member's, so they aren't in your totals."

    /// Short tag on each shared-room row.
    public static let roomTag = "Shared room"
}
