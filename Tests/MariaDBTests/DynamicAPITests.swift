import Foundation
import Testing
@testable import MariaDB
import PerfectCRUD

// MARK: - Perfect-CRUD's Dynamic API (select / mutate / execute) on a live server
//
// Run with: MARIA_TESTS=1 MARIA_TEST_PORT=… [MARIA_TEST_HOST=… MARIA_TEST_USER=…
// MARIA_TEST_PASSWORD=…] swift test --filter DynamicAPITests

private let schema = "perfect_maria_dynamic_test"
private let clientMultiStatements: UInt = 1 << 16

private func connection(_ database: String, flag: UInt = 0) throws -> MySQL {
	let mysql = MySQL()
	mysql.setOption(.MYSQL_SET_CHARSET_NAME, "utf8mb4")
	guard mysql.connect(host: MariaTestEnvironment.host, user: MariaTestEnvironment.user,
	                    password: MariaTestEnvironment.password, db: database,
	                    port: UInt32(MariaTestEnvironment.port), flag: flag) else {
		throw MySQLCRUDError("Could not connect. \(mysql.errorMessage())")
	}
	return mysql
}

private func freshDatabase(flag: UInt = 0) throws -> Database<MySQLDatabaseConfiguration> {
	let admin = Database(configuration: MySQLDatabaseConfiguration(connection: try connection("mysql")))
	try admin.sql("DROP DATABASE IF EXISTS `\(schema)`")
	try admin.sql("CREATE DATABASE `\(schema)` DEFAULT CHARACTER SET utf8mb4")
	return Database(configuration: MySQLDatabaseConfiguration(connection: try connection(schema, flag: flag)))
}

private func dropSchema() {
	guard let mysql = try? connection("mysql") else { return }
	_ = mysql.query(statement: "DROP DATABASE IF EXISTS `\(schema)`")
	mysql.close()
}

private func count(_ db: Database<MySQLDatabaseConfiguration>, _ table: String) throws -> Int {
	struct Count: Codable { let c: Int }
	let rows = try db.sql("SELECT COUNT(*) AS c FROM `\(table)`", Count.self)
	return rows[0].c
}

@Suite("Dynamic API on a live server", .serialized)
struct DynamicAPITests {

	@Test(.mariaLive)
	func selectReturnsTypedRows() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("""
			CREATE TABLE `items` (`id` INT PRIMARY KEY, `name` VARCHAR(20), `price` DOUBLE,
			`qty` SMALLINT UNSIGNED, `data` VARBINARY(8), `note` TEXT NULL)
			""")
		try db.sql("INSERT INTO `items` VALUES (1, 'one', 1.5, 7, X'00FF', NULL), (2, 'two', 2.5, 8, X'01', 'n')")
		let result = try db.select(DynamicQuery(
			table: "items",
			predicates: [.init(field: "id", comparison: .greaterThanOrEqual, value: .int(1))],
			orderings: [.init(field: "id", descending: true)],
			limit: 10))
		#expect(result.rows.count == 2)
		let first = try #require(result.rows.first)
		#expect(first["id"] == .int(2))
		#expect(first["NAME"] == .string("two"))
		#expect(first["price"] == .double(2.5))
		#expect(first["qty"] == .uint(8))
		#expect(first["data"] == .bytes([0x01]))
		#expect(first["note"] == .string("n"))
		#expect(result.rows[1]["note"] == .null)
		#expect(result.rows[1]["data"] == .bytes([0x00, 0xFF]))
	}

	// CRUD 3.0.0's DynamicRow.init lowercases the column names and traps on a duplicate key.
	// The connector keeps the first of the columns whose names differ only by case, or not
	// at all, so a join or an alias can't crash the process.
	@Test(.mariaLive)
	func columnsDifferingOnlyByCaseKeepTheFirst() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		var result = try db.execute(DynamicSQL(sql: "SELECT 1 AS a, 2 AS A, 3 AS `a`"))
		#expect(result.rows.count == 1)
		#expect(result.rows.first?["a"] == .int(1))
		#expect(result.rows.first?.values.count == 1)

		try db.sql("CREATE TABLE `parent` (`id` INT PRIMARY KEY, `Name` VARCHAR(20))")
		try db.sql("CREATE TABLE `child` (`id` INT PRIMARY KEY, `parentId` INT, `name` VARCHAR(20))")
		try db.sql("INSERT INTO `parent` VALUES (1, 'P')")
		try db.sql("INSERT INTO `child` VALUES (10, 1, 'c')")
		result = try db.execute(DynamicSQL(sql: """
			SELECT p.id, p.Name, c.id, c.name FROM `parent` p JOIN `child` c ON c.parentId = p.id
			"""))
		let row = try #require(result.rows.first)
		#expect(row["id"] == .int(1))
		#expect(row["name"] == .string("P"))
		#expect(row.values.count == 2)
	}

	@Test(.mariaLive)
	func mutateReportsAffectedRowsAndInsertedID() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `auto` (`id` INT AUTO_INCREMENT PRIMARY KEY, `v` INT)")
		var result = try db.mutate(DynamicMutation(action: .insert, table: "auto", values: ["v": .int(5)]))
		#expect(result.affectedRows == 1)
		#expect(result.insertedID == 1)
		result = try db.mutate(DynamicMutation(action: .insert, table: "auto", values: ["v": .int(6)]))
		#expect(result.insertedID == 2)
		result = try db.mutate(DynamicMutation(
			action: .update, table: "auto", values: ["v": .int(0)],
			predicates: [.init(field: "v", comparison: .greaterThan, value: .int(0))]))
		#expect(result.affectedRows == 2)
		#expect(result.insertedID == nil)
		result = try db.mutate(DynamicMutation(
			action: .delete, table: "auto",
			predicates: [.init(field: "id", comparison: .equal, value: .int(1))]))
		#expect(result.affectedRows == 1)
		result = try db.execute(DynamicSQL(sql: "SELECT * FROM `auto`"))
		#expect(result.rows.count == 1)
		#expect(result.affectedRows == 0)
	}

	// Unsigned values bind as unsigned: no Int conversion that could trap or wrap.
	@Test(.mariaLive)
	func extremeIntegersRoundTrip() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `nums` (`id` INT PRIMARY KEY, `u` BIGINT UNSIGNED, `s` BIGINT)")
		_ = try db.mutate(DynamicMutation(action: .insert, table: "nums",
		                              values: ["id": .int(1), "u": .uint(UInt64.max), "s": .int(Int64.min)]))
		_ = try db.execute(DynamicSQL(sql: "INSERT INTO `nums` VALUES (?, ?, ?)",
		                          bindings: [.uint(2), .uint(UInt64(Int64.max) + 1), .int(Int64.max)]))
		let result = try db.select(DynamicQuery(
			table: "nums", predicates: [.init(field: "u", comparison: .greaterThan, value: .uint(UInt64(Int64.max)))],
			orderings: [.init(field: "id")]))
		#expect(result.rows.map { $0["u"] } == [.uint(UInt64.max), .uint(UInt64(Int64.max) + 1)])
		#expect(result.rows.map { $0["s"] } == [.int(Int64.min), .int(Int64.max)])
	}

	// A prepared statement holds one statement, so multi-statement text fails as a whole,
	// before any of it runs, rather than running only the first statement.
	@Test(.mariaLive)
	func multipleStatementsRunAllOrThrow() throws {
		let db = try freshDatabase()
		defer { dropSchema() }
		try db.sql("CREATE TABLE `m` (`id` INT PRIMARY KEY)")
		#expect(throws: (any Error).self) {
			try db.execute(DynamicSQL(sql: "INSERT INTO `m` VALUES (1); INSERT INTO `m` VALUES (2)",
			                          allowsMultipleStatements: true))
		}
		#expect(try count(db, "m") == 0)
		// Text starting with a statement that runs unprepared needs CLIENT_MULTI_STATEMENTS;
		// without it the server rejects the whole text.
		#expect(throws: (any Error).self) {
			try db.execute(DynamicSQL(sql: "BEGIN; INSERT INTO `m` VALUES (1); COMMIT",
			                          allowsMultipleStatements: true))
		}
		#expect(try count(db, "m") == 0)

		// With CLIENT_MULTI_STATEMENTS, every statement runs.
		let multi = Database(configuration: MySQLDatabaseConfiguration(
			connection: try connection(schema, flag: clientMultiStatements)))
		_ = try multi.execute(DynamicSQL(sql: "BEGIN; INSERT INTO `m` VALUES (1); INSERT INTO `m` VALUES (2); COMMIT",
		                             allowsMultipleStatements: true))
		#expect(try count(db, "m") == 2)
		// ...and an error in a later statement is reported.
		#expect(throws: (any Error).self) {
			try multi.execute(DynamicSQL(sql: "BEGIN; INSERT INTO `m` VALUES (3); INSERT INTO `m` VALUES (1); COMMIT",
			                             allowsMultipleStatements: true))
		}
		_ = multi.configuration.connection.query(statement: "ROLLBACK")
	}
}
