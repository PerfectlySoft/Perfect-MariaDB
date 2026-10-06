import Foundation
import Testing
@testable import MariaDB
import PerfectCRUD

// MARK: - MySQLStmtExeDelegate result handling on a live server
//
// Run with: MARIA_TESTS=1 MARIA_TEST_PORT=… [MARIA_TEST_HOST=… MARIA_TEST_USER=…
// MARIA_TEST_PASSWORD=…] swift test --filter StatementResultTests

private let schema = "perfect_maria_stmt_result_test"

private func connection(_ database: String) throws -> MySQL {
	let mysql = MySQL()
	mysql.setOption(.MYSQL_SET_CHARSET_NAME, "utf8mb4")
	guard mysql.connect(host: MariaTestEnvironment.host, user: MariaTestEnvironment.user,
	                    password: MariaTestEnvironment.password, db: database,
	                    port: UInt32(MariaTestEnvironment.port)) else {
		throw MySQLCRUDError("Could not connect. \(mysql.errorMessage())")
	}
	return mysql
}

private func freshDatabase() throws -> Database<MySQLDatabaseConfiguration> {
	let admin = Database(configuration: MySQLDatabaseConfiguration(connection: try connection("mysql")))
	try admin.sql("DROP DATABASE IF EXISTS `\(schema)`")
	try admin.sql("CREATE DATABASE `\(schema)` DEFAULT CHARACTER SET utf8mb4")
	return Database(configuration: MySQLDatabaseConfiguration(connection: try connection(schema)))
}

private func dropSchema() {
	guard let mysql = try? connection("mysql") else { return }
	_ = mysql.query(statement: "DROP DATABASE IF EXISTS `\(schema)`")
	mysql.close()
}

private struct Pair: Codable, Equatable { let id: Int; let name: String }

@Suite("Statement results on a live server", .serialized)
struct StatementResultTests {

	// Codable decoding used a [name: index] map built from a dictionary, so with duplicate
	// names the column that won depended on dictionary order.
	@Test(.mariaLive)
	func duplicateColumnNamesDecodeTheFirst() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		for _ in 0..<20 {
			let rows = try db.sql("SELECT 1 AS id, 'a' AS name, 2 AS id, 'b' AS name", Pair.self)
			#expect(rows == [Pair(id: 1, name: "a")])
		}
	}
}
