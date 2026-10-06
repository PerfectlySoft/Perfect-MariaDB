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

	// A subquery returning two rows fails with error 1242 while the result is being read.
	// mysql_stmt_store_result's failure was ignored and mysql_stmt_fetch then crashed inside
	// libmariadb (SIGSEGV); now the error is thrown and the connection stays usable.
	@Test(.mariaLive)
	func errorWhileReadingRowsThrows() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `a` (`id` INT PRIMARY KEY)")
		try db.sql("CREATE TABLE `b` (`k` INT, `x` INT)")
		try db.sql("INSERT INTO `a` VALUES (1), (2), (3)")
		try db.sql("INSERT INTO `b` VALUES (1, 10), (2, 20), (2, 21)")
		struct Row: Codable { let id: Int; let x: Int? }
		let sql = "SELECT id, (SELECT x FROM b WHERE b.k = a.id) AS x FROM a ORDER BY id"
		#expect(throws: MySQLCRUDError.self) { try db.sql(sql, Row.self) }
		#expect(throws: MySQLCRUDError.self) { try db.execute(DynamicSQL(sql: sql)) }
		// The raw statement API reports it too.
		let stmt = MySQLStmt(db.configuration.connection)
		#expect(stmt.prepare(statement: sql))
		#expect(stmt.execute())
		let results = stmt.results()
		#expect(results.next() == nil)
		#expect(results.failed)
		#expect(results.errorCode == 1242, "\(results.errorMessage)")
		// The connection still works.
		#expect(try db.sql("SELECT id, NULL AS x FROM a ORDER BY id", Row.self).map(\.id) == [1, 2, 3])
	}
}
