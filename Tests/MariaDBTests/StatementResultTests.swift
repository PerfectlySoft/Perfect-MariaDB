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
		stmt.reset()
		#expect(stmt.execute())
		#expect(!stmt.results().forEachRow { _ in })
		// The connection still works.
		#expect(try db.sql("SELECT id, NULL AS x FROM a ORDER BY id", Row.self).map(\.id) == [1, 2, 3])
	}

	// A statement prepared again gets a bind array sized for the new statement, and one that's
	// executed, read and reset many times keeps working. (The bind array used to leak on every
	// parameterized statement; that was checked with `leaks`, which a test can't run.)
	@Test(.mariaLive)
	func statementsRebindAfterResetAndReprepare() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		let stmt = MySQLStmt(db.configuration.connection)
		for i in 0..<50 {
			#expect(stmt.prepare(statement: "SELECT ?, ?"))
			stmt.bindParam(i)
			stmt.bindParam("x\(i)")
			#expect(stmt.execute(), "\(stmt.errorMessage())")
			let row = stmt.results().next()
			#expect(row?[0] as? Int64 == Int64(i))
			#expect(row?[1] as? String == "x\(i)")
			stmt.reset()
		}
		#expect(stmt.prepare(statement: "SELECT ?, ?, ?"))
		stmt.bindParam(1)
		stmt.bindParam(2)
		stmt.bindParam(3)
		#expect(stmt.execute(), "\(stmt.errorMessage())")
		#expect(stmt.results().next()?.count == 3)
	}

	// DECIMAL values arrive as text; Double and Float properties used to read them as 0.
	@Test(.mariaLive)
	func decimalColumnsDecodeIntoFloatingPoint() throws {
		struct Price: Codable, TableNameProvider {
			static let tableName = "decimal_price"
			let id: Int
			let amount: Double
			let rate: Float
			let optional: Double?
		}
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE decimal_price (id INT PRIMARY KEY, amount DECIMAL(12,2), rate DECIMAL(5,3), optional DECIMAL(8,4) NULL)")
		try db.sql("INSERT INTO decimal_price VALUES (1, 1234.56, 0.125, NULL), (2, -0.50, 2.5, 3.1415)")
		let prices = try db.table(Price.self).order(by: \.id).select().map { $0 }
		#expect(prices.map(\.amount) == [1234.56, -0.5])
		#expect(prices.map(\.rate) == [0.125, 2.5])
		#expect(prices.map(\.optional) == [nil, 3.1415])
	}

	// Blob parameters (bindParam([UInt8]), ([Int8]) and (_:length:)) are freed on reset, and a
	// statement reused with blobs of different sizes, including empty ones, keeps working. (The
	// buffers used to leak; that was checked with `leaks`, which a test can't run.)
	@Test(.mariaLive)
	func blobParametersSurviveResetAndReuse() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		let stmt = MySQLStmt(db.configuration.connection)
		for i in 0..<50 {
			#expect(stmt.prepare(statement: "SELECT ?, ?, ?"))
			let bytes = [UInt8](repeating: UInt8(i), count: i)
			stmt.bindParam(bytes)
			stmt.bindParam([Int8](repeating: 7, count: 50 - i))
			"abc".withCString { stmt.bindParam($0, length: 3) }
			#expect(stmt.execute(), "\(stmt.errorMessage())")
			// MariaDB returns a blob parameter's SELECT as bytes; MySQL 8.4 as text.
			func asBytes(_ value: Any?) -> [UInt8]? {
				(value as? [UInt8]) ?? (value as? String).map { Array($0.utf8) }
			}
			let row = stmt.results().next()
			#expect(asBytes(row?[0]) == bytes)
			#expect(asBytes(row?[1])?.count == 50 - i)
			#expect(asBytes(row?[2]) == Array("abc".utf8))
			stmt.reset()
		}
	}

	// Reusing a statement (execute, read results, reset, execute again) corrupted the heap with
	// libmysqlclient: the client library kept pointers into the freed Results' buffers and wrote
	// through them on the next execute (Perfect-MySQL 376a1c3).
	@Test(.mariaLive)
	func aStatementCanBeReusedAfterReadingResults() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		let stmt = MySQLStmt(db.configuration.connection)
		try #require(stmt.prepare(statement: "SELECT CAST(? AS SIGNED) AS n, ? * 1.5 AS d, CONCAT('v', ?) AS s, LENGTH(?) AS l"))
		for n in 0..<300 {
			stmt.bindParam(n)
			stmt.bindParam(Double(n))
			stmt.bindParam("\(n)")
			stmt.bindParam([UInt8](repeating: 1, count: n % 9))
			try #require(stmt.execute(), "\(n): \(stmt.errorMessage())")
			let row = stmt.results().next()
			#expect(row?[0] as? Int64 == Int64(n))
			#expect(row?[2] as? String == "v\(n)")
			// LENGTH() is an INT on MariaDB and a BIGINT on MySQL.
			#expect((row?[3] as? any BinaryInteger).map { Int64($0) } == Int64(n % 9))
			stmt.reset()
		}
	}

	// An [Int8] property read its blob with Int8($0), which traps on any byte >= 0x80, so a
	// negative value crashed on the way back. The rows are written with SQL here: Perfect-CRUD
	// 3.0.0 itself traps encoding a negative [Int8] (fixed in Perfect-CRUD 3.0.1).
	@Test(.mariaLive)
	func signedByteArraysRoundTrip() throws {
		struct Signed: Codable, TableNameProvider {
			static let tableName = "signed_bytes"
			let id: Int
			let bytes: [Int8]
		}
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.create(Signed.self, policy: .dropTable)
		let written = [Signed(id: 1, bytes: [-1, -128, 0, 127, 1]), Signed(id: 2, bytes: [])]
		try db.sql("INSERT INTO signed_bytes (id, bytes) VALUES (1, X'FF80007F01'), (2, X'')")
		let read = try db.table(Signed.self).order(by: \.id).select().map { $0 }
		#expect(read.map(\.bytes) == written.map(\.bytes))
	}

	// A CALL has no result metadata until it runs, and it ends with an extra status result.
	// The column maps were built before execute(), so every column read as missing (Codable
	// threw, Dynamic rows were empty), and the leftover result had to be drained.
	@Test(.mariaLive)
	func callReturnsRowsAndLeavesTheConnectionUsable() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `t` (`id` INT PRIMARY KEY, `name` VARCHAR(10))")
		try db.sql("INSERT INTO `t` VALUES (1, 'one'), (2, 'two'), (3, 'three')")
		try db.sql("CREATE PROCEDURE `rows_from`(IN lo INT) SELECT id, name FROM t WHERE id >= lo ORDER BY id")
		try db.sql("CREATE PROCEDURE `two_sets`() BEGIN SELECT id, name FROM t WHERE id = 1; SELECT 9 AS id, 'x' AS name; END")

		#expect(try db.sql("CALL rows_from(?)", bindings: [("?", .integer(2))], Pair.self)
			== [Pair(id: 2, name: "two"), Pair(id: 3, name: "three")])
		#expect(try db.sql("SELECT id, name FROM t WHERE id = 1", Pair.self) == [Pair(id: 1, name: "one")])

		let dynamic = try db.execute(DynamicSQL(sql: "CALL rows_from(3)"))
		#expect(dynamic.rows == [DynamicRow(["id": .int(3), "name": .string("three")])])
		#expect(try db.sql("SELECT id, name FROM t WHERE id = 2", Pair.self) == [Pair(id: 2, name: "two")])

		// Only the first result set of a multi-result CALL is read; the rest are discarded.
		#expect(try db.sql("CALL two_sets()", Pair.self) == [Pair(id: 1, name: "one")])
		#expect(try db.sql("SELECT id, name FROM t WHERE id = 3", Pair.self) == [Pair(id: 3, name: "three")])

		// A CALL run without reading its rows, then more statements, in a transaction.
		try db.transaction {
			try db.sql("CALL two_sets()")
			try db.sql("CALL rows_from(1)")
			try db.sql("UPDATE t SET name = 'uno' WHERE id = 1")
		}
		#expect(try db.sql("SELECT id, name FROM t WHERE id = 1", Pair.self) == [Pair(id: 1, name: "uno")])
	}

	// A CALL whose first result set is fine but whose later statement fails used to report
	// success with the first set's rows: draining the remaining results dropped the error.
	// Untyped `db.sql("CALL ...")` reads one row at most and can't see it (Perfect-CRUD calls
	// hasNext() once), which the README documents.
	@Test(.mariaLive)
	func errorAfterACallsFirstResultSetThrows() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `u` (`id` INT PRIMARY KEY)")
		try db.sql("INSERT INTO `u` VALUES (1)")
		try db.sql("CREATE PROCEDURE `dup`() BEGIN SELECT 1 AS id, 'a' AS name; INSERT INTO u VALUES (1); END")
		try db.sql("CREATE PROCEDURE `sub`() BEGIN SELECT 1 AS id, 'a' AS name; SELECT (SELECT 1 UNION SELECT 2) AS id, 'b' AS name; END")
		try db.sql("CREATE PROCEDURE `sig`() BEGIN SELECT 1 AS id, 'a' AS name; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'boom'; END")
		for call in ["CALL dup()", "CALL sub()", "CALL sig()"] {
			#expect(throws: MySQLCRUDError.self, "\(call)") { try db.sql(call, Pair.self) }
			#expect(throws: MySQLCRUDError.self, "\(call)") { try db.execute(DynamicSQL(sql: call)) }
			// The connection still works afterwards.
			#expect(try db.sql("SELECT 2 AS id, 'ok' AS name", Pair.self) == [Pair(id: 2, name: "ok")])
			// Untyped: Perfect-CRUD calls hasNext() once, so the error can't be reported (it's
			// logged), but the connection must still be usable.
			try db.sql(call)
			#expect(try db.sql("SELECT 3 AS id, 'ok' AS name", Pair.self) == [Pair(id: 3, name: "ok")])
		}
		// A CALL that succeeds still doesn't throw.
		try db.sql("CREATE PROCEDURE `fine`() BEGIN SELECT 1 AS id, 'a' AS name; SELECT 2 AS id, 'b' AS name; END")
		#expect(try db.sql("CALL fine()", Pair.self) == [Pair(id: 1, name: "a")])
	}

	// MariaDB's INSERT ... RETURNING returns rows from an INSERT.
	@Test(.mariaLive)
	func insertReturningReturnsRows() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		let version = try db.sql("SELECT VERSION() AS v", Version.self).first?.v ?? ""
		guard version.contains("MariaDB") else { return } // MySQL has no RETURNING
		try db.sql("CREATE TABLE `r` (`id` INT AUTO_INCREMENT PRIMARY KEY, `name` VARCHAR(10))")
		let result = try db.execute(DynamicSQL(
			sql: "INSERT INTO `r` (`name`) VALUES (?), (?) RETURNING id, name",
			bindings: [.string("a"), .string("b")]))
		#expect(result.rows == [DynamicRow(["id": .int(1), "name": .string("a")]),
		                        DynamicRow(["id": .int(2), "name": .string("b")])])
		#expect(result.affectedRows == 2)
		#expect(result.insertedID == nil)
		#expect(try db.sql("INSERT INTO `r` (`name`) VALUES ('c') RETURNING id, name", Pair.self)
			== [Pair(id: 3, name: "c")])
		#expect(try count(db) == 3)
	}
}

private struct Version: Codable { let v: String }

private func count(_ db: Database<MySQLDatabaseConfiguration>) throws -> Int {
	struct C: Codable { let c: Int }
	return try db.sql("SELECT COUNT(*) AS c FROM `r`", C.self)[0].c
}
