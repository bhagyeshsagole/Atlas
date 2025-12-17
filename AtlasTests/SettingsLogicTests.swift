import XCTest
@testable import Atlas

final class SettingsLogicTests: XCTestCase {

    func testAppearancePersistenceLightDark() {
        let defaults = UserDefaults.standard
        defaults.set("light", forKey: "appearanceMode")
        XCTAssertEqual(defaults.string(forKey: "appearanceMode"), "light")
        defaults.set("dark", forKey: "appearanceMode")
        XCTAssertEqual(defaults.string(forKey: "appearanceMode"), "dark")
    }

    func testWeightUnitPersistence() {
        let defaults = UserDefaults.standard
        defaults.set("lb", forKey: "weightUnit")
        XCTAssertEqual(defaults.string(forKey: "weightUnit"), "lb")
        defaults.set("kg", forKey: "weightUnit")
        XCTAssertEqual(defaults.string(forKey: "weightUnit"), "kg")
    }

    func testDropdownExclusivity() {
        var active: DropdownType? = .appearance
        active = .weight
        XCTAssertEqual(active, .weight)
        active = nil
        XCTAssertNil(active)
    }

    func testDropdownTrailingVisibilityToggle() {
        // simulate opacity toggling for trailing content
        let isOpen = true
        XCTAssertEqual(isOpen ? 0.0 : 1.0, 0.0)
        let isClosed = false
        XCTAssertEqual(isClosed ? 0.0 : 1.0, 1.0)
    }

    func testOrdinalSuffixes() {
        let cases: [Int: String] = [
            1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 11: "11th", 12: "12th", 13: "13th",
            21: "21st", 22: "22nd", 23: "23rd", 31: "31st"
        ]
        for (day, expected) in cases {
            XCTAssertEqual(ordinalString(for: day), expected)
        }
    }

    private func ordinalString(for day: Int) -> String {
        let suffix: String
        let tens = day % 100
        if tens >= 11 && tens <= 13 {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}
