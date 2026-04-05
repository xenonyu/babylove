import XCTest
@testable import BabyLove

final class BabyModelTests: XCTestCase {

    // MARK: - Age Text

    func testAgeNewborn() {
        let baby = Baby(name: "T", birthDate: Date(), gender: .girl)
        XCTAssertTrue(baby.ageText.contains("0") || baby.ageText.contains("day"))
    }

    func testAgeWeeks() {
        let d = Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date())!
        let baby = Baby(name: "T", birthDate: d, gender: .boy)
        XCTAssertTrue(baby.ageText.contains("2"))
    }

    func testAgeMonths() {
        let d = Calendar.current.date(byAdding: .month, value: -5, to: Date())!
        let baby = Baby(name: "T", birthDate: d, gender: .girl)
        XCTAssertTrue(baby.ageText.contains("5"))
    }

    func testAgeYears() {
        let d = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        let baby = Baby(name: "T", birthDate: d, gender: .boy)
        XCTAssertTrue(baby.ageText.contains("1"))
    }

    func testAgeInDays() {
        let d = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let baby = Baby(name: "T", birthDate: d, gender: .other)
        XCTAssertEqual(baby.ageInDays, 10)
    }

    func testAgeInMonths() {
        let d = Calendar.current.date(byAdding: .month, value: -4, to: Date())!
        let baby = Baby(name: "T", birthDate: d, gender: .girl)
        XCTAssertEqual(baby.ageInMonths, 4)
    }

    // MARK: - Gender

    func testGenderDisplayNames() {
        XCTAssertFalse(Baby.Gender.boy.displayName.isEmpty)
        XCTAssertFalse(Baby.Gender.girl.displayName.isEmpty)
        XCTAssertFalse(Baby.Gender.other.displayName.isEmpty)
    }

    func testGenderIcons() {
        for g in Baby.Gender.allCases {
            XCTAssertFalse(g.icon.isEmpty)
            XCTAssertFalse(g.color.isEmpty)
        }
    }

    // MARK: - Codable

    func testBabyCodable() throws {
        let baby = Baby(name: "Emma", birthDate: Date(timeIntervalSince1970: 0), gender: .girl)
        let data = try JSONEncoder().encode(baby)
        let decoded = try JSONDecoder().decode(Baby.self, from: data)
        XCTAssertEqual(decoded.name, baby.name)
        XCTAssertEqual(decoded.gender, baby.gender)
        XCTAssertEqual(decoded.id, baby.id)
    }
}
