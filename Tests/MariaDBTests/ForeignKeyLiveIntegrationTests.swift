import Foundation
import Testing
import PerfectCRUD
@testable import MariaDB

// MARK: - ADR-0001 Phase 4: live FOREIGN KEY behavior (MariaDB connector)
//
// Mirrors Perfect-MySQL's ForeignKeyLiveIntegrationTests.swift. This
// machine has no separate MariaDB server running (only a real mysqld) --
// libmariadb is wire-protocol-compatible with a real MySQL server, so this
// still exercises the actual connector code path (DDL generation, bind,
// execute, row decode) against a real server, just not against MariaDB's
// own server binary specifically. Env-var driven (not the older hardcoded
// root/123 in MariaDBTests.swift, which doesn't match this server) so it
// can point at whatever's actually running.

private struct FKLiveParent: Codable {
	var id: Int
	var name: String
}

private struct FKLiveChild: Codable {
	var id: Int
	@ForeignKey(FKLiveParent.self, onDelete: cascade, onUpdate: restrict)
	var parentId: Int
}

private struct FKFixtureConfig {
	let host: String
	let port: Int?
	let adminDatabase: String
	let username: String
	let password: String
	let schema: String

	static func fromEnvironment(schemaSuffix: String = UUID().uuidString.replacingOccurrences(of: "-", with: "_")) -> Self {
		let env = ProcessInfo.processInfo.environment
		return FKFixtureConfig(
			host: env["MARIA_TEST_HOST"] ?? "127.0.0.1",
			port: env["MARIA_TEST_PORT"].flatMap(Int.init),
			adminDatabase: env["MARIA_TEST_ADMIN_DATABASE"] ?? "mysql",
			username: env["MARIA_TEST_USER"] ?? "root",
			password: env["MARIA_TEST_PASSWORD"] ?? "",
			schema: "perfect_maria_fixture_\(schemaSuffix)"
		)
	}
}

private final class ForeignKeyFixtureDatabase {
	let config: FKFixtureConfig
	let database: Database<MySQLDatabaseConfiguration>

	init(config: FKFixtureConfig = .fromEnvironment()) throws {
		self.config = config
		let admin = try Database(configuration: MySQLDatabaseConfiguration(
			database: config.adminDatabase, host: config.host, port: config.port,
			username: config.username, password: config.password
		))
		try admin.sql("DROP DATABASE IF EXISTS `\(config.schema)`")
		try admin.sql("CREATE DATABASE `\(config.schema)` DEFAULT CHARACTER SET utf8mb4")

		database = try Database(configuration: MySQLDatabaseConfiguration(
			database: config.schema, host: config.host, port: config.port,
			username: config.username, password: config.password
		))
		try database.create(FKLiveParent.self, primaryKey: \FKLiveParent.id, policy: .shallow)
		try database.create(FKLiveChild.self, primaryKey: \FKLiveChild.id, policy: .shallow)
	}

	deinit {
		do {
			let admin = try Database(configuration: MySQLDatabaseConfiguration(
				database: config.adminDatabase, host: config.host, port: config.port,
				username: config.username, password: config.password
			))
			try admin.sql("DROP DATABASE IF EXISTS `\(config.schema)`")
		} catch {
			Issue.record("Could not drop fixture schema \(config.schema): \(error)")
		}
	}
}

struct ForeignKeyLiveIntegrationTests {

	@Test(.enabled(if: ProcessInfo.processInfo.environment["MARIA_FK_LIVE_TESTS"] == "1"))
	func onDeleteCascadeActuallyRemovesTheChildRow() throws {
		let fixture = try ForeignKeyFixtureDatabase()
		let db = fixture.database

		try db.table(FKLiveParent.self).insert(FKLiveParent(id: 1, name: "Acme"))
		try db.table(FKLiveChild.self).insert(FKLiveChild(id: 1, parentId: ForeignKey(FKLiveParent.self, onDelete: cascade, onUpdate: restrict, wrappedValue: 1)))

		let beforeDelete = try db.table(FKLiveChild.self).where(\FKLiveChild.id == 1).select().map { $0 }
		#expect(beforeDelete.count == 1)

		try db.table(FKLiveParent.self).where(\FKLiveParent.id == 1).delete()

		let afterDelete = try db.table(FKLiveChild.self).where(\FKLiveChild.id == 1).select().map { $0 }
		#expect(afterDelete.isEmpty)
	}

	@Test(.enabled(if: ProcessInfo.processInfo.environment["MARIA_FK_LIVE_TESTS"] == "1"))
	func insertingAChildWithAnUnknownParentIsRejected() throws {
		let fixture = try ForeignKeyFixtureDatabase()
		let db = fixture.database

		#expect(throws: (any Error).self) {
			try db.table(FKLiveChild.self).insert(FKLiveChild(id: 1, parentId: ForeignKey(FKLiveParent.self, onDelete: cascade, onUpdate: restrict, wrappedValue: 999)))
		}
	}
}
