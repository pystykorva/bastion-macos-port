import SwiftUI
import TessuCore

/// The overall judgement from a scan report. It is deliberately cautious: doors Tessu could not test are
/// never counted as closed.
struct Verdict {
    enum Level { case clear, review, danger, blind }
    var level: Level

    /// The checks that actually test the router's doors. "All doors closed" needs every one of them OK.
    static let doorIds = ["tr069", "upnp", "telnet", "ssh", "web-admin-http"]

    enum Doors { case closed, blind, partial }

    static func doors(_ checks: [CheckResult]) -> Doors {
        let doors = doorIds.map { id in checks.first { $0.id == id } }
        if doors.allSatisfy({ $0?.status == .ok }) { return .closed }
        if doors.allSatisfy({ $0 == nil || $0?.status == .unknown }) { return .blind }
        return .partial
    }

    static func untestedDoors(_ checks: [CheckResult]) -> Int {
        doorIds.filter { id in checks.first { $0.id == id }?.status != .ok }.count
    }

    static func of(_ report: ScanReport) -> Verdict {
        let c = report.checks
        if c.contains(where: { $0.status == .risk && ($0.severity == .critical || $0.severity == .high) }) { return Verdict(level: .danger) }
        if c.contains(where: { $0.status == .risk || $0.status == .warn }) { return Verdict(level: .review) }
        switch doors(c) {
        case .closed: return Verdict(level: .clear)
        case .blind: return Verdict(level: .blind)
        case .partial: return Verdict(level: .review)
        }
    }

    var headline: String {
        switch level {
        case .clear: return "All doors closed"
        case .review: return "Needs a look"
        case .danger: return "A door is open"
        case .blind: return "Could not test"
        }
    }

    var symbol: String {
        switch level {
        case .clear: return "checkmark.shield.fill"
        case .review: return "eye.trianglebadge.exclamationmark.fill"
        case .danger: return "exclamationmark.octagon.fill"
        case .blind: return "questionmark.shield"
        }
    }

    var color: Color {
        switch level {
        case .clear: return Theme.color(.ok)
        case .review: return Theme.color(.warn)
        case .danger: return Theme.color(.risk)
        case .blind: return .secondary
        }
    }

    /// Findings that need attention, most urgent first: open before review before unknown, then by severity.
    static func ranked(_ checks: [CheckResult]) -> [CheckResult] {
        checks.filter { $0.status != .ok }
            .sorted { ($0.status.rank, $0.severity.rank) < ($1.status.rank, $1.severity.rank) }
    }
}
