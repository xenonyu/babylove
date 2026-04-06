import Foundation
import SwiftUI

struct Baby: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var birthDate: Date
    var gender: Gender
    var photoData: Data?

    enum Gender: String, Codable, CaseIterable {
        case boy, girl, other

        var displayName: String {
            switch self {
            case .boy:   return String(localized: "gender.boy")
            case .girl:  return String(localized: "gender.girl")
            case .other: return String(localized: "gender.other")
            }
        }

        var icon: String {
            switch self {
            case .boy:   return "👦"
            case .girl:  return "👧"
            case .other: return "🧒"
            }
        }

        var color: String {
            switch self {
            case .boy:   return "#7EC8EA"
            case .girl:  return "#EAAEB3"
            case .other: return "#B3AAEA"
            }
        }
    }

    // MARK: - Age Helpers

    /// Primary age components (year, month, remaining days).
    /// NOTE: `.weekOfYear` is intentionally excluded — including it causes
    /// `.day` to return only the remainder after whole weeks are subtracted,
    /// which makes the displayed day count wrong for babies older than 1 month.
    var ageComponents: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: birthDate, to: Date())
    }

    var ageText: String {
        Self.formatAge(from: ageComponents)
    }

    /// Localized age string (e.g. "3m 12d old" in English, "3m 12d" in CJK).
    /// Uses the `age.format` key from Localizable.strings which supports
    /// languages where the "old" suffix is unnecessary (Chinese, Japanese, Korean).
    var localizedAge: String {
        String(format: String(localized: "age.format"), ageText)
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: birthDate, to: Date()).day ?? 0
    }

    var ageInMonths: Int {
        let c = Calendar.current.dateComponents([.month], from: birthDate, to: Date())
        return c.month ?? 0
    }

    /// Human-readable age text at a specific date (e.g. "3m 12d", "1y 2m").
    /// Useful for growth records where the measurement date may differ from today.
    func ageText(at date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: birthDate, to: date)
        return Self.formatAge(from: c)
    }

    // MARK: - Localized Age Formatting

    /// Convert age components into a localized abbreviated string.
    /// Uses keys from Localizable.strings: age.ym, age.y, age.md, age.m, age.wd, age.w, age.d
    private static func formatAge(from c: DateComponents) -> String {
        let yr = c.year ?? 0
        let mo = c.month ?? 0
        let dy = c.day ?? 0

        // Guard against future or same-day dates
        guard yr >= 0 && mo >= 0 && dy >= 0 else {
            return String(format: NSLocalizedString("age.d", comment: ""), 0)
        }

        if yr > 0 {
            return mo > 0
                ? String(format: NSLocalizedString("age.ym", comment: ""), yr, mo)
                : String(format: NSLocalizedString("age.y", comment: ""), yr)
        } else if mo > 0 {
            return dy > 0
                ? String(format: NSLocalizedString("age.md", comment: ""), mo, dy)
                : String(format: NSLocalizedString("age.m", comment: ""), mo)
        } else if dy >= 7 {
            let wk = dy / 7
            let remDays = dy % 7
            return remDays > 0
                ? String(format: NSLocalizedString("age.wd", comment: ""), wk, remDays)
                : String(format: NSLocalizedString("age.w", comment: ""), wk)
        } else {
            return String(format: NSLocalizedString("age.d", comment: ""), dy)
        }
    }
}
