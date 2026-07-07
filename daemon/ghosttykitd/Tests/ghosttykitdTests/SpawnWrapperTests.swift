import Foundation
@testable import ghosttykitd
import XCTest

final class SpawnWrapperTests: XCTestCase {
    func testEscapeLeavesSafeCharactersAlone() {
        XCTAssertEqual(shellWordEscape("/opt/ghosttykit/bin/gty"), "/opt/ghosttykit/bin/gty")
        XCTAssertEqual(shellWordEscape("abc-DEF_123.file"), "abc-DEF_123.file")
        XCTAssertEqual(shellWordEscape("GTY_SOCK=/opt/run/gk.sock"), "GTY_SOCK=/opt/run/gk.sock")
    }

    func testEscapeBackslashesUnsafeCharacters() {
        XCTAssertEqual(shellWordEscape("a b"), "a\\ b")
        XCTAssertEqual(shellWordEscape("it's"), "it\\'s")
        XCTAssertEqual(shellWordEscape(#"say "hi""#), #"say\ \"hi\""#)
        XCTAssertEqual(shellWordEscape("$HOME"), "\\$HOME")
        XCTAssertEqual(shellWordEscape(#"back\slash"#), #"back\\slash"#)
        XCTAssertEqual(shellWordEscape("a;b"), "a\\;b")
        XCTAssertEqual(shellWordEscape("a  b"), "a\\ \\ b")
        XCTAssertEqual(shellWordEscape("a\nb"), "a\\\nb")
        XCTAssertEqual(shellWordEscape("a>b&c|d`e"), "a\\>b\\&c\\|d\\`e")
    }

    func testEscapedWordRoundTripsThroughShellParsing() throws {
        let hostile = #"it's "quoted" $HOME \back\ ; two  spaces"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(shellWordEscape(hostile))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        XCTAssertEqual(output, hostile)
    }

    func testWrapsCommandBehindClaim() {
        let command = testSpawnWrapper().command(token: "token-1", wrapping: "/bin/zsh -ilc 'nvim .'")

        XCTAssertEqual(
            command,
            "/bin/sh -c GTY_SOCK=/opt/run/gk.sock\\ /opt/ghosttykit/bin/gty\\ spawn-claim\\ token-1" +
                "\\ \\>/dev/null\\ 2\\>\\&1\\;\\ exec\\ /bin/zsh\\ -ilc\\ \\'nvim\\ .\\'"
        )
    }

    func testWrapsLoginShellWhenNoCommandGiven() {
        let command = testSpawnWrapper().command(token: "token-1", wrapping: nil)

        XCTAssertEqual(
            command,
            "/bin/sh -c GTY_SOCK=/opt/run/gk.sock\\ /opt/ghosttykit/bin/gty\\ spawn-claim\\ token-1" +
                "\\ \\>/dev/null\\ 2\\>\\&1\\;\\ exec\\ -l\\ /bin/zsh"
        )
    }

    func testEscapesGtyPathAndLoginShellInsideScript() {
        let wrapper = SpawnWrapper(
            gtyPath: "/Applications/My Tools/gty",
            socketPath: "/opt/run/gk.sock",
            loginShell: { "/opt/odd shell/fish" }
        )

        let command = wrapper.command(token: "t", wrapping: nil)

        XCTAssertTrue(command.contains("/Applications/My\\\\\\ Tools/gty"))
        XCTAssertTrue(command.contains("/opt/odd\\\\\\ shell/fish"))
    }
}
