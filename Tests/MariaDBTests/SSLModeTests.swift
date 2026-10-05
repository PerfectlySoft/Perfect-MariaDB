import Foundation
import Testing
@testable import MariaDB

// MYSQL_OPT_SSL_MODE takes MySQL's SSL_MODE_* values; libmariadb has no such option, so
// MySQL.setOption maps the modes onto MYSQL_OPT_SSL_ENFORCE / MYSQL_OPT_SSL_VERIFY_SERVER_CERT.
//
// The server under test must have TLS enabled (MariaDB 11.4+ and MySQL 8.4 do by default, with a
// self-signed certificate). Set MARIA_TEST_NOTLS_PORT (and MARIA_TEST_NOTLS_HOST if it differs) to a
// server started without TLS (e.g. MariaDB with --skip-ssl) to also check that modes requiring TLS
// refuse it.

private let host = MariaTestEnvironment.host
private let user = MariaTestEnvironment.user
private let password = MariaTestEnvironment.password
private let noTLSHost = MariaTestEnvironment.noTLSHost

// A throwaway CA that signed nothing; no server certificate verifies against it.
private let unrelatedCA = """
-----BEGIN CERTIFICATE-----
MIIDNzCCAh+gAwIBAgIUebI8rhKIvneUhW73TBnjUFTuJtkwDQYJKoZIhvcNAQEL
BQAwKjEoMCYGA1UEAwwfUGVyZmVjdC1NeVNRTCB1bnJlbGF0ZWQgdGVzdCBDQTAg
Fw0yNjEwMDUwODU3MTZaGA8yMTI2MDkxMTA4NTcxNlowKjEoMCYGA1UEAwwfUGVy
ZmVjdC1NeVNRTCB1bnJlbGF0ZWQgdGVzdCBDQTCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBANPwPYQ3W+wFh7okRwcbo9iD2Js6+ObplZ6AuuTSpa3kXWD2
ARLNCDD0QHmimUHvM6b7kPGB4Db83mm6nyjoKhpPhTcQ00nd4IjOu5fxk0UYNWsP
/N45JYLJrxn5OI0GD4iRnRNH9cOFBYkYujRG2lEfhxSdtLc2xzkb+pJqvnLLpmqy
Nv0Hmf+yE1JOMoHQl4OoL/JlrthIPLUPEwbxX4X9+AUSLAZJauwx6qrrAt/Ss8q0
mF8wgRBfKZvxGNgU4VJFeojffgHnZ0MnyDbCPhmcEIm1CI4S7It/Lr1utrezCDId
AAC1AtJOeIDEdeP2rheF54klxb9ft2/ouK6zs7cCAwEAAaNTMFEwHQYDVR0OBBYE
FPU6jP961PeieRBt/Qa7gxOog8mPMB8GA1UdIwQYMBaAFPU6jP961PeieRBt/Qa7
gxOog8mPMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAMWTI7n4
l6ygnISCYaiJCqq6D/NlYeKYJ+VVuYAhrKJJVBiM87EYmEgMSNZh8oeiuWkunxhv
h5EKvBj6yKcTlD8SW52ldI5D25kRlBj9nVHNzc3c/gDsXQCxkhdHZ1W4Tb4dm1hu
fGWNrMtP2EUKrBGDHBHCB9rQewYU4IpPoIwb3errVe6PqrW7tGpR2cAjMvb6RHPO
L1GIJS2lX4m9GKebgY40xg63fAZSjkZMeuwQ0LlD0wukKv4wE3TDD5fF9SG074H6
Al2cua7CXLLNrciOS/MN1CcPOM7AHmniTMPvVtpMdIvXyxI8LX+i0jqUh5jCyvsm
ioamVHL6w6te45I=
-----END CERTIFICATE-----
"""

@Suite struct SSLModeTests {
    // The values of MySQL's enum mysql_ssl_mode (SSL_MODE_DISABLED ... SSL_MODE_VERIFY_IDENTITY).
    enum Mode: Int, CaseIterable {
        case disabled = 1, preferred, required, verifyCA, verifyIdentity
    }

    private func connect(_ mode: Mode, host: String = host, port: Int = MariaTestEnvironment.port, ca: String? = nil, reconnect: Bool = false) -> MySQL {
        let mysql = MySQL()
        mysql.setOption(.MYSQL_OPT_CONNECT_TIMEOUT, 5)
        if reconnect {
            #expect(mysql.setOption(.MYSQL_OPT_RECONNECT, true))
        }
        if let ca {
            #expect(mysql.setOption(.MYSQL_OPT_SSL_CA, ca))
        }
        #expect(mysql.setOption(.MYSQL_OPT_SSL_MODE, mode.rawValue), "setOption(MYSQL_OPT_SSL_MODE, \(mode)) failed: \(mysql.errorMessage())")
        _ = mysql.connect(host: host, user: user, password: password, db: "mysql", port: UInt32(port))
        return mysql
    }

    private func cipher(_ mysql: MySQL) -> String? {
        guard mysql.query(statement: "SHOW SESSION STATUS LIKE 'Ssl_cipher'"),
              let results = mysql.storeResults(),
              let row = results.next() else {
            Issue.record("Ssl_cipher query failed: \(mysql.errorMessage())")
            return nil
        }
        return row[1] ?? ""
    }

    @Test(.mariaLive) func encryptedModesUseTLS() {
        for mode in [Mode.preferred, .required] {
            let mysql = connect(mode)
            #expect(mysql.errorCode() == 0, "\(mode): \(mysql.errorMessage())")
            #expect(cipher(mysql) != "", "\(mode) connected without TLS")
        }
    }

    @Test(.mariaLive) func disabledModeUsesPlaintext() {
        let mysql = connect(.disabled)
        #expect(mysql.errorCode() == 0, "\(mysql.errorMessage())")
        #expect(cipher(mysql) == "")
    }

    @Test(.mariaLive) func verifyingModesRejectAnUntrustedServer() throws {
        let caFile = FileManager.default.temporaryDirectory.appendingPathComponent("perfect-mariadb-unrelated-ca-\(UUID()).pem")
        try unrelatedCA.write(to: caFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: caFile) }
        for mode in [Mode.verifyCA, .verifyIdentity] {
            let mysql = connect(mode, ca: caFile.path)
            #expect(mysql.errorCode() != 0, "\(mode) accepted a certificate the CA didn't sign")
            #expect(!mysql.ping())
        }
    }

    // Connector/C 3.4 deliberately skips verification on loopback connections without a CA.
    @Test(.mariaLive, .enabled(if: !["127.0.0.1", "::1"].contains(host), "needs a non-loopback MARIA_TEST_HOST"))
    func verifyingModesRejectASelfSignedServerWithoutCA() {
        for mode in [Mode.verifyCA, .verifyIdentity] {
            let mysql = connect(mode)
            #expect(mysql.errorCode() != 0, "\(mode) accepted a self-signed certificate")
            #expect(!mysql.ping())
        }
    }

    @Test(.mariaLive) func requiredModeTurnsOffReconnect() throws {
        let mysql = connect(.required, reconnect: true)
        #expect(mysql.errorCode() == 0, "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT CONNECTION_ID()"), "\(mysql.errorMessage())")
        let id = try #require(mysql.storeResults()?.next()?[0] ?? nil)
        let killer = MySQL()
        #expect(killer.connect(host: host, user: user, password: password, db: "mysql", port: UInt32(MariaTestEnvironment.port)), "\(killer.errorMessage())")
        #expect(killer.query(statement: "KILL \(id)"), "\(killer.errorMessage())")
        #expect(!mysql.ping(), "reconnected; a reconnect isn't checked for TLS")
    }

    @Test func unknownModeIsRejected() {
        let mysql = MySQL()
        for value in [0, 6, -1, Int(UInt32.max) + 3] {
            #expect(!mysql.setOption(.MYSQL_OPT_SSL_MODE, value), "accepted SSL mode \(value)")
        }
    }

    @Test(.mariaLive, .enabled(if: MariaTestEnvironment.noTLSPort != nil, Comment(rawValue: MariaTestEnvironment.noTLSSkipReason ?? "")))
    func modesRequiringTLSRefuseAPlaintextServer() throws {
        let noTLSPort = try #require(MariaTestEnvironment.noTLSPort)
        for mode in [Mode.required, .verifyCA, .verifyIdentity] {
            let mysql = connect(mode, host: noTLSHost, port: noTLSPort)
            #expect(mysql.errorCode() == 2026 /* CR_SSL_CONNECTION_ERROR */, "\(mode): \(mysql.errorMessage())")
            #expect(!mysql.errorMessage().isEmpty)
            #expect(!mysql.ping(), "\(mode) left a plaintext connection open")
        }
        // A retry on the same handle is refused too: a failed connect mustn't drop the SSL mode.
        for mode in [Mode.required, .verifyIdentity] {
            let mysql = connect(mode, host: noTLSHost, port: noTLSPort)
            #expect(mysql.errorCode() == 2026)
            #expect(!mysql.connect(host: noTLSHost, user: user, password: password, port: UInt32(noTLSPort)), "\(mode) retry connected")
            #expect(mysql.errorCode() == 2026, "\(mode) retry: \(mysql.errorMessage())")
            #expect(!mysql.ping())
        }
        for mode in [Mode.disabled, .preferred] {
            let mysql = connect(mode, host: noTLSHost, port: noTLSPort)
            #expect(mysql.errorCode() == 0, "\(mode): \(mysql.errorMessage())")
            #expect(cipher(mysql) == "")
        }
    }
}
