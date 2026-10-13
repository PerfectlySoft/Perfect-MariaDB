import Foundation
import Testing
@testable import MariaDB
import mariadbclient

// MARK: - listTables(wildcard:) / listDatabases(wildcard:)
//
// libmariadb's mysql_list_tables / mysql_list_dbs paste the wildcard into
// "SHOW TABLES LIKE '%s'" without escaping it. A `'` in the wildcard ended the string literal:
// a name containing one couldn't be listed, and on a connection with CLIENT_MULTI_STATEMENTS
// the rest of the wildcard ran as further statements.

private let schema = "perfect_maria_wildcard_test"
private let clientMultiStatements: UInt = 1 << 16

private func connect(charset: String = "utf8mb4", flag: UInt = 0) -> MySQL {
    let mysql = MySQL()
    _ = mysql.setOption(.MYSQL_OPT_CONNECT_TIMEOUT, 5)
    _ = mysql.setOption(.MYSQL_SET_CHARSET_NAME, charset)
    _ = mysql.connect(host: MariaTestEnvironment.host, user: MariaTestEnvironment.user,
                      password: MariaTestEnvironment.password, port: UInt32(MariaTestEnvironment.port), flag: flag)
    return mysql
}

private func freshSchema() -> MySQL {
    let mysql = connect()
    _ = mysql.query(statement: "DROP DATABASE IF EXISTS `\(schema)`")
    _ = mysql.query(statement: "CREATE DATABASE `\(schema)` DEFAULT CHARACTER SET utf8mb4")
    _ = mysql.selectDatabase(named: schema)
    return mysql
}

private func dropSchema() {
    let mysql = connect()
    _ = mysql.query(statement: "DROP DATABASE IF EXISTS `\(schema)`")
    _ = mysql.query(statement: "DROP DATABASE IF EXISTS `\(schema)'db`")
    mysql.close()
}

@Suite("listTables / listDatabases wildcards on a live server", .serialized)
struct ListingWildcardTests {
    @Test(.mariaLive)
    func wildcardWithAQuoteMatchesTheName() throws {
        let mysql = freshSchema()
        defer { mysql.close(); dropSchema() }
        #expect(mysql.query(statement: "CREATE TABLE `it's` (id INT)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE `plain` (id INT)"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "it's") == ["it's"])
        #expect(mysql.listTables(wildcard: "it'%") == ["it's"])
        #expect(mysql.listTables().sorted() == ["it's", "plain"])
        // A backslash is the LIKE escape character: `\_` matches only a literal underscore.
        #expect(mysql.query(statement: "CREATE TABLE `a_b` (id INT)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE `axb` (id INT)"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "a_b").sorted() == ["a_b", "axb"])
        #expect(mysql.listTables(wildcard: #"a\_b"#) == ["a_b"])
        // Under NO_BACKSLASH_ESCAPES a quote has to be doubled rather than backslashed.
        #expect(mysql.query(statement: "SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES')"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "it's") == ["it's"])
        // MariaDB keeps `\` as the LIKE escape character in this mode; MySQL treats it as a
        // literal character, so `a\_b` matches neither table there.
        let isMariaDB = mysql.query(statement: "SELECT VERSION()")
            && (mysql.storeResults()?.next()?[0] ?? nil)?.contains("MariaDB") == true
        #expect(mysql.listTables(wildcard: #"a\_b"#) == (isMariaDB ? ["a_b"] : []))
        #expect(mysql.query(statement: "SET SESSION sql_mode = DEFAULT"), "\(mysql.errorMessage())")

        #expect(mysql.query(statement: "CREATE DATABASE `\(schema)'db`"), "\(mysql.errorMessage())")
        #expect(mysql.listDatabases(wildcard: "\(schema)'db") == ["\(schema)'db"])
        #expect(mysql.listDatabases(wildcard: "\(schema)%").sorted() == [schema, "\(schema)'db"])
    }

    // On main the DROP ran: "SHOW TABLES LIKE 'x'; DROP TABLE wild_victim; -- '". Under gbk the
    // escaping has to follow the connection's charset: 中 is E4 B8 AD in UTF-8, and AD followed
    // by the backslash that escapes the quote is one gbk character. Under big5 on x86_64,
    // libmariadb 3.3's mysql_real_escape_string turned E4 B8 AD 27 into E4 B8 AD 5C 27, so the
    // DROP ran even with escaping; wildcards like that are now refused under the five charsets
    // where 0x5C can be a trail byte.
    @Test(.mariaLive, arguments: ["utf8mb4", "latin1", "gbk", "big5", "cp932", "sjis", "gb18030"])
    func wildcardCannotRunAnotherStatement(charset: String) throws {
        let setup = freshSchema()
        defer { setup.close(); dropSchema() }
        let listings: [(String, (MySQL, String) -> [String])] = [
            ("listTables", { $0.listTables(wildcard: $1) }),
            ("listDatabases", { $0.listDatabases(wildcard: $1) })]
        for wildcard in ["x'; DROP TABLE wild_victim; -- ", "中'; DROP TABLE wild_victim; -- ",
                         "中\\'; DROP TABLE wild_victim; -- ", "ｱ'; DROP TABLE wild_victim; -- "] {
            for (name, list) in listings {
                #expect(setup.query(statement: "CREATE TABLE IF NOT EXISTS `wild_victim` (id INT)"), "\(setup.errorMessage())")
                let mysql = connect(charset: charset, flag: clientMultiStatements)
                #expect(mysql.selectDatabase(named: schema))
                #expect(list(mysql, wildcard) == [])
                // Wait for any further statements to finish, so the check below doesn't race them.
                while mysql.moreResults() { _ = mysql.nextResult() }
                mysql.close()
                #expect(setup.listTables(wildcard: "wild_victim") == ["wild_victim"], "\(name) \(charset) \(wildcard)")
            }
        }
    }

    // The refusal applies only where it's needed: a byte >= 0x80 together with `'` or `\`, under
    // big5, cp932, gbk, gb18030 or sjis.
    @Test(.mariaLive)
    func unsafeWildcardsAreRefusedOnlyUnderTrailByteCharsets() throws {
        for charset in ["big5", "cp932", "gbk", "gb18030", "sjis"] {
            let mysql = connect(charset: charset)
            defer { mysql.close() }
            // MariaDB 11.8 has no gb18030; the client then stays on its default (utf8mb4), where
            // nothing needs refusing.
            let actual = String(cString: mysql_character_set_name(mysql.ptr!))
            #expect(mysql.listingWildcardIsUnsafe("中'") == (actual == charset), "\(charset), client charset \(actual)")
            #expect(mysql.listingWildcardIsUnsafe("中\\") == (actual == charset), "\(charset), client charset \(actual)")
            #expect(!mysql.listingWildcardIsUnsafe("中%"), "\(charset)")
            #expect(!mysql.listingWildcardIsUnsafe("it's"), "\(charset)")
            #expect(!mysql.listingWildcardIsUnsafe(#"a\_b"#), "\(charset)")
            #expect(!mysql.listingWildcardIsUnsafe(nil), "\(charset)")
        }
        for charset in ["utf8mb4", "latin1"] {
            let mysql = connect(charset: charset)
            defer { mysql.close() }
            #expect(!mysql.listingWildcardIsUnsafe("中'"), "\(charset)")
            #expect(!mysql.listingWildcardIsUnsafe("中\\"), "\(charset)")
        }
        // Ordinary wildcards still work under such a charset.
        let setup = freshSchema()
        defer { setup.close(); dropSchema() }
        #expect(setup.query(statement: "CREATE TABLE `it's` (id INT)"), "\(setup.errorMessage())")
        let big5 = connect(charset: "big5")
        defer { big5.close() }
        #expect(big5.selectDatabase(named: schema))
        #expect(big5.listTables(wildcard: "it's") == ["it's"])
        #expect(big5.listTables(wildcard: "it%") == ["it's"])
    }

    // Under NO_BACKSLASH_ESCAPES quotes are doubled instead of backslash-escaped, and wildcards keep
    // working; injection stays closed. (Perfect-MySQL's test, adapted.)
    @Test(.mariaLive, arguments: ["utf8mb4", "big5"])
    func wildcardsWorkUnderNoBackslashEscapes(charset: String) throws {
        let setup = freshSchema()
        defer { setup.close(); dropSchema() }
        #expect(setup.query(statement: "CREATE TABLE `victim` (i INT)"), "\(setup.errorMessage())")
        #expect(setup.query(statement: "CREATE TABLE `it's` (i INT)"), "\(setup.errorMessage())")
        let mysql = connect(charset: charset, flag: clientMultiStatements)
        defer { mysql.close() }
        #expect(mysql.selectDatabase(named: schema))
        #expect(mysql.query(statement: "SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES')"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "vic%") == ["victim"], "\(charset)")
        #expect(mysql.listTables(wildcard: "it's") == ["it's"], "\(charset)")
        #expect(mysql.listDatabases(wildcard: schema) == [schema], "\(charset)")
        for payload in ["x'; DROP TABLE victim; -- ", "x\\'; DROP TABLE victim; -- ", "中'; DROP TABLE victim; -- "] {
            #expect(mysql.listTables(wildcard: payload).isEmpty, "\(charset)")
            while mysql.moreResults() { _ = mysql.nextResult() }
            #expect(mysql.query(statement: "SELECT 1"), "\(charset): \(mysql.errorMessage())")
            _ = mysql.storeResults()
        }
        #expect(setup.listTables(wildcard: "victim") == ["victim"])
    }

    // libmariadb (and libmysqlclient) choose between backslash-escaping and quote-doubling from the
    // NO_BACKSLASH_ESCAPES bit in the server's last status. After a stored routine changes
    // sql_mode, both servers leave that bit as the routine set it while the session's sql_mode is
    // restored, so the client escaped for the wrong mode and a wildcard could end the literal:
    // the DROP below ran. A `'` is now always doubled (valid in both modes), and a wildcard with
    // both `'` and `\` is refused.
    @Test(.mariaLive)
    func wildcardsStaySafeWhenARoutineLeavesTheModeBitStale() throws {
        let setup = freshSchema()
        defer { setup.close(); dropSchema() }
        #expect(setup.query(statement: "CREATE PROCEDURE clear_mode() SET SESSION sql_mode = ''"), "\(setup.errorMessage())")
        #expect(setup.query(statement: "CREATE PROCEDURE set_nbe() SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'"), "\(setup.errorMessage())")
        #expect(setup.query(statement: "CREATE TABLE `it's` (i INT)"), "\(setup.errorMessage())")
        let scenarios: [(String, String, String)] = [
            // session mode before, routine, payload
            ("NO_BACKSLASH_ESCAPES", "clear_mode", "x'; DROP TABLE victim; -- "),
            ("", "set_nbe", "x\\'; DROP TABLE victim; -- "),
            ("", "set_nbe", "x'; DROP TABLE victim; -- "),
        ]
        for (mode, routine, payload) in scenarios {
            #expect(setup.query(statement: "CREATE TABLE IF NOT EXISTS `victim` (id INT)"), "\(setup.errorMessage())")
            let mysql = connect(flag: clientMultiStatements)
            #expect(mysql.selectDatabase(named: schema))
            #expect(mysql.query(statement: "SET SESSION sql_mode = '\(mode)'"), "\(mysql.errorMessage())")
            #expect(mysql.query(statement: "CALL \(routine)()"), "\(mysql.errorMessage())")
            while mysql.moreResults() { _ = mysql.storeResults(); if mysql.nextResult() != 0 { break } }
            #expect(mysql.listTables(wildcard: payload).isEmpty, "\(routine) \(payload)")
            #expect(mysql.listTables(wildcard: "it's") == ["it's"], "\(routine)")
            while mysql.moreResults() { _ = mysql.nextResult() }
            mysql.close()
            #expect(setup.listTables(wildcard: "victim") == ["victim"], "\(routine) \(payload)")
        }
    }
}

