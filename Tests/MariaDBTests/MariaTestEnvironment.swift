//
//  MariaTestEnvironment.swift
//  MariaDBTests
//
//  Live-server settings shared by every test file:
//
//    MARIA_TESTS=1                 enable the live tests
//    MARIA_TEST_PORT               required, 1...65535 -- there is no default
//    MARIA_TEST_HOST               default 127.0.0.1; "localhost" and "" are refused
//    MARIA_TEST_USER               default root
//    MARIA_TEST_PASSWORD           default 123 (the foreign-key tests default to empty)
//    MARIA_TEST_NOTLS_HOST/PORT    optional TLS-less server for SSLModeTests, checked the same way
//
//  Live tests are skipped unless MARIA_TESTS=1, MARIA_TEST_PORT is a valid port
//  and the host isn't "localhost" or empty. libmariadb connects to port 0 as its
//  default port, 3306, which would point drop-and-recreate tests at whatever
//  MySQL server happens to be running locally; it reaches "localhost" (and an
//  empty host, which means localhost) through the Unix socket, ignoring the port
//  entirely; and UInt32(port) traps on a negative port.
//

import Foundation
import Testing

enum MariaTestEnvironment {
	private static let env = ProcessInfo.processInfo.environment

	static let host = trimmed(env["MARIA_TEST_HOST"]) ?? "127.0.0.1"
	static let user = env["MARIA_TEST_USER"] ?? "root"
	static let password = password(default: "123")
	private static let rawPort = validPort(env["MARIA_TEST_PORT"])

	/// MARIA_TEST_PASSWORD, or `defaultValue` when it isn't set (even to empty).
	static func password(default defaultValue: String) -> String {
		env["MARIA_TEST_PASSWORD"] ?? defaultValue
	}

	/// Why live tests are skipped, or nil when they are enabled.
	static var skipReason: String? {
		if env["MARIA_TESTS"] != "1" { return "set MARIA_TESTS=1 to enable live MariaDB tests" }
		if rawPort == nil { return "set MARIA_TEST_PORT to a test server's port, 1...65535 (3306 is never assumed)" }
		if usesSocket(host) { return "MARIA_TEST_HOST=localhost (or empty) uses the Unix socket and ignores the port; use 127.0.0.1" }
		return nil
	}

	/// True only when MARIA_TESTS=1, MARIA_TEST_PORT is a valid port and the host isn't "localhost" or empty.
	static var isEnabled: Bool { skipReason == nil }

	/// The configured test server's port. Use only from tests gated on `isEnabled`
	/// (`.mariaLive`); anything else traps rather than reaching a server on 3306.
	static var port: Int {
		precondition(isEnabled, "MariaTestEnvironment.port read while live tests are disabled: \(skipReason ?? "")")
		return rawPort!
	}

	/// The optional TLS-less server for SSLModeTests, checked like the main one.
	static let noTLSHost = trimmed(env["MARIA_TEST_NOTLS_HOST"]) ?? host

	/// Why the TLS-less server tests are skipped, or nil when they are enabled.
	static var noTLSSkipReason: String? {
		if let skipReason { return skipReason }
		if validPort(env["MARIA_TEST_NOTLS_PORT"]) == nil { return "set MARIA_TEST_NOTLS_PORT to a server without TLS, 1...65535" }
		if usesSocket(noTLSHost) { return "MARIA_TEST_NOTLS_HOST=localhost (or empty) uses the Unix socket and ignores the port" }
		return nil
	}

	/// The TLS-less server's port, or nil when `noTLSSkipReason` is set.
	static var noTLSPort: Int? {
		noTLSSkipReason == nil ? validPort(env["MARIA_TEST_NOTLS_PORT"]) : nil
	}

	private static func validPort(_ value: String?) -> Int? {
		value.flatMap(Int.init).flatMap { (1...65535).contains($0) ? $0 : nil }
	}

	private static func trimmed(_ value: String?) -> String? {
		value?.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// libmariadb connects to "localhost" and to an empty host through the Unix socket.
	private static func usesSocket(_ host: String) -> Bool {
		host.isEmpty || host.lowercased() == "localhost"
	}
}

extension Trait where Self == ConditionTrait {
	/// Runs the test only against a configured live server (see `MariaTestEnvironment`);
	/// otherwise it's reported as skipped, with the reason.
	static var mariaLive: Self {
		.enabled(if: MariaTestEnvironment.isEnabled, Comment(rawValue: MariaTestEnvironment.skipReason ?? ""))
	}
}
