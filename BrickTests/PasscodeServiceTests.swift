import XCTest
@testable import Brick

final class PasscodeServiceTests: XCTestCase {
    func testGeneratedPasscodeIsSixDigits() {
        for _ in 0..<50 {
            let code = PasscodeService.generateRandom()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { $0.isNumber })
        }
    }

    func testUserChosenValidation() {
        XCTAssertTrue(PasscodeService.isValidUserChosen("1234"))
        XCTAssertTrue(PasscodeService.isValidUserChosen("12345"))
        XCTAssertTrue(PasscodeService.isValidUserChosen("123456"))
        XCTAssertFalse(PasscodeService.isValidUserChosen("123"))
        XCTAssertFalse(PasscodeService.isValidUserChosen("1234567"))
        XCTAssertFalse(PasscodeService.isValidUserChosen("12a4"))
        XCTAssertFalse(PasscodeService.isValidUserChosen(""))
    }

    func testSaltChangesHash() {
        let a = PasscodeService.makeSalt()
        let b = PasscodeService.makeSalt()
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(
            PasscodeService.hash("1234", salt: a),
            PasscodeService.hash("1234", salt: b)
        )
    }

    func testVerifyRoundTrip() {
        let salt = PasscodeService.makeSalt()
        let hash = PasscodeService.hash("987654", salt: salt)
        XCTAssertTrue(PasscodeService.verify("987654", hash: hash, salt: salt))
        XCTAssertFalse(PasscodeService.verify("987653", hash: hash, salt: salt))
        XCTAssertFalse(PasscodeService.verify("", hash: hash, salt: salt))
    }

    func testVerifyRejectsWrongSalt() {
        let salt = PasscodeService.makeSalt()
        let hash = PasscodeService.hash("4242", salt: salt)
        let wrongSalt = PasscodeService.makeSalt()
        XCTAssertFalse(PasscodeService.verify("4242", hash: hash, salt: wrongSalt))
    }

    func testHashIsDeterministicForSameInputs() {
        let salt = PasscodeService.makeSalt()
        let h1 = PasscodeService.hash("1234", salt: salt)
        let h2 = PasscodeService.hash("1234", salt: salt)
        XCTAssertEqual(h1, h2)
    }
}
