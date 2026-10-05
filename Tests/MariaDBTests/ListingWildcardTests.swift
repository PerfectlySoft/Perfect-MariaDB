import Foundation
import Testing
@testable import MariaDB

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
        #expect(mysql.listTables(wildcard: #"a\_b"#) == ["a_b"])
        #expect(mysql.query(statement: "SET SESSION sql_mode = DEFAULT"), "\(mysql.errorMessage())")

        #expect(mysql.query(statement: "CREATE DATABASE `\(schema)'db`"), "\(mysql.errorMessage())")
        #expect(mysql.listDatabases(wildcard: "\(schema)'db") == ["\(schema)'db"])
        #expect(mysql.listDatabases(wildcard: "\(schema)%").sorted() == [schema, "\(schema)'db"])
    }

    // On main the DROP ran: "SHOW TABLES LIKE 'x'; DROP TABLE wild_victim; -- '". Under gbk the
    // escaping has to follow the connection's charset: 中 is E4 B8 AD in UTF-8, and AD followed
    // by the backslash that escapes the quote is one gbk character.
    @Test(.mariaLive, arguments: ["utf8mb4", "gbk", "big5"])
    func wildcardCannotRunAnotherStatement(charset: String) throws {
        let setup = freshSchema()
        defer { setup.close(); dropSchema() }
        let listings: [(String, (MySQL, String) -> [String])] = [
            ("listTables", { $0.listTables(wildcard: $1) }),
            ("listDatabases", { $0.listDatabases(wildcard: $1) })]
        for wildcard in ["x'; DROP TABLE wild_victim; -- ", "中'; DROP TABLE wild_victim; -- "] {
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
}
