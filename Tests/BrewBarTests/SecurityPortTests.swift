// Copyright © 2026 Dennis Stewart. All rights reserved.

import XCTest
@testable import BrewBarKit

final class SecurityPortTests: XCTestCase {

    private let fixture = """
    p412
    cpostgres
    f7
    n127.0.0.1:5432
    f8
    n[::1]:5432
    p9001
    cnode
    f21
    n*:3000
    p73
    cmDNSResponder
    f11
    n*:5353
    """

    func testParsesMultiplePidsAndMultipleAddressesPerPid() {
        let listeners = SecurityService.parseListeners(fixture)
        XCTAssertEqual(listeners, [
            SecurityService.ListeningSocket(pid: 412, command: "postgres", address: "127.0.0.1:5432"),
            SecurityService.ListeningSocket(pid: 412, command: "postgres", address: "[::1]:5432"),
            SecurityService.ListeningSocket(pid: 9001, command: "node", address: "*:3000"),
            SecurityService.ListeningSocket(pid: 73, command: "mDNSResponder", address: "*:5353"),
        ])
    }

    func testCommandDoesNotLeakIntoNextProcessRecord() {
        // A process record with no `c` line must not inherit the previous command.
        let output = """
        p100
        credis-server
        n*:6379
        p101
        n*:6380
        """
        let listeners = SecurityService.parseListeners(output)
        XCTAssertEqual(listeners.map(\.command), ["redis-server", ""])
    }

    func testIgnoresMalformedLines() {
        let output = """
        n10.0.0.1:1
        garbage without a tag
        pNOTANUMBER
        cghost
        n*:9999
        p0
        n*:9998
        p555
        cvalid
        n*:8080
        x*:1234
        n
        """
        let listeners = SecurityService.parseListeners(output)
        XCTAssertEqual(listeners, [
            SecurityService.ListeningSocket(pid: 555, command: "valid", address: "*:8080"),
        ])
    }

    func testEmptyOutputYieldsNoListeners() {
        XCTAssertTrue(SecurityService.parseListeners("").isEmpty)
        XCTAssertTrue(SecurityService.parseListeners("\n\n").isEmpty)
    }

    func testHomebrewPrefixMatchRespectsPathBoundary() {
        let prefix = "/opt/homebrew"
        XCTAssertTrue(SecurityService.isHomebrewExecutable("/opt/homebrew/bin/redis-server", prefix: prefix))
        XCTAssertTrue(SecurityService.isHomebrewExecutable("/opt/homebrew/opt/postgresql@16/bin/postgres", prefix: prefix))
        XCTAssertTrue(SecurityService.isHomebrewExecutable("/opt/homebrew/bin/redis-server", prefix: "/opt/homebrew/"))

        XCTAssertFalse(SecurityService.isHomebrewExecutable("/opt/homebrewevil/bin/redis-server", prefix: prefix))
        XCTAssertFalse(SecurityService.isHomebrewExecutable("/opt/homebrew", prefix: prefix))
        XCTAssertFalse(SecurityService.isHomebrewExecutable("/usr/sbin/sshd", prefix: prefix))
        XCTAssertFalse(SecurityService.isHomebrewExecutable("/Applications/Some.app/Contents/MacOS/homebrew-helper", prefix: prefix))
    }

    func testCellarPathCountsAsHomebrew() {
        XCTAssertTrue(SecurityService.isHomebrewExecutable("/usr/local/Cellar/nginx/1.27.0/bin/nginx", prefix: "/opt/homebrew"))
    }

    func testResolvesOwnExecutablePath() throws {
        let path = try XCTUnwrap(SecurityService.executablePath(forPid: getpid()))
        XCTAssertTrue(path.hasPrefix("/"), "expected absolute path, got \(path)")
    }

    func testUnknownPidHasNoExecutablePath() {
        XCTAssertNil(SecurityService.executablePath(forPid: Int32.max))
    }
}
