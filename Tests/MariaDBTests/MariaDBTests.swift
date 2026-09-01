import Foundation
import Testing
@testable import MariaDB
import PerfectCRUD

// Run with: MARIA_TESTS=1 swift test -Xcc -I/opt/homebrew/Cellar/mariadb-connector-c/3.4.9/include/mariadb PKG_CONFIG_PATH=/opt/homebrew/opt/mariadb-connector-c/lib/pkgconfig swift test

private let testHost = "127.0.0.1"
private let testUser = "root"
private let testPassword = "123"
private let testSchema = "test"
private let testDB = "test"
private let testDBRowCount = 5
private typealias DBConfiguration = MySQLDatabaseConfiguration

private var mariaEnabled: Bool { ProcessInfo.processInfo.environment["MARIA_TESTS"] == "1" }

private func makeMySQL() -> MySQL {
    let m = MySQL()
    _ = m.setOption(.MYSQL_OPT_CONNECT_TIMEOUT, 5)
    _ = m.setOption(.MYSQL_SET_CHARSET_NAME, "utf8mb4")
    _ = m.connect(host: testHost, user: testUser, password: testPassword)
    if m.selectDatabase(named: testSchema) == false {
        _ = m.query(statement: "CREATE SCHEMA `\(testSchema)` DEFAULT CHARACTER SET utf8mb4")
        _ = m.selectDatabase(named: testSchema)
    }
    return m
}

private var rawMySQL: MySQL {
    let mysql = MySQL()
    _ = mysql.setOption(.MYSQL_OPT_CONNECT_TIMEOUT, 5)
    _ = mysql.setOption(.MYSQL_SET_CHARSET_NAME, "utf8mb4")
    _ = mysql.connect(host: testHost, user: testUser, password: testPassword, db: "mysql")
    _ = mysql.query(statement: "CREATE DATABASE IF NOT EXISTS \(testDB) DEFAULT CHARACTER SET utf8mb4")
    _ = mysql.selectDatabase(named: testDB)
    return mysql
}

private func getDB(reset: Bool = true) throws -> Database<DBConfiguration> {
    if reset {
        let db = Database(configuration: try DBConfiguration(
            database: "mysql", host: testHost, username: testUser, password: testPassword))
        try db.sql("DROP DATABASE IF EXISTS \(testDB)")
        try db.sql("CREATE DATABASE \(testDB) DEFAULT CHARACTER SET utf8mb4")
    }
    return Database(configuration: try DBConfiguration(
        database: testDB, host: testHost, username: testUser, password: testPassword))
}

private struct TestTable1: Codable, TableNameProvider {
    enum CodingKeys: String, CodingKey {
        case id, name, integer = "int", double = "doub", blob, subTables
    }
    static let tableName = "test_table_1"
    let id: Int
    let name: String?
    let integer: Int?
    let double: Double?
    let blob: [UInt8]?
    let subTables: [TestTable2]?
    init(id: Int, name: String? = nil, integer: Int? = nil, double: Double? = nil, blob: [UInt8]? = nil, subTables: [TestTable2]? = nil) {
        self.id = id; self.name = name; self.integer = integer; self.double = double; self.blob = blob; self.subTables = subTables
    }
}

private struct TestTable2: Codable {
    let id: UUID
    let parentId: Int
    let date: Date
    let name: String?
    let int: Int?
    let doub: Double?
    let blob: [UInt8]?
    init(id: UUID, parentId: Int, date: Date, name: String? = nil, int: Int? = nil, doub: Double? = nil, blob: [UInt8]? = nil) {
        self.id = id; self.parentId = parentId; self.date = date
        self.name = name; self.int = int; self.doub = doub; self.blob = blob
    }
}

private func getTestDB() throws -> Database<DBConfiguration> {
    let db = try getDB()
    try db.create(TestTable1.self, policy: .dropTable)
    _ = try db.transaction {
        try db.table(TestTable1.self).insert((1...testDBRowCount).map { num -> TestTable1 in
            let n = UInt8(num)
            let blob: [UInt8]? = (num % 2 != 0) ? nil : [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5)
            return TestTable1(id: num, name: "This is name bind \(num)", integer: num, double: Double(num), blob: blob)
        })
    }
    _ = try db.transaction {
        try db.table(TestTable2.self).insert((1...testDBRowCount).flatMap { parentId -> [TestTable2] in
            (1...testDBRowCount).map { num -> TestTable2 in
                let n = UInt8(num)
                let blob: [UInt8]? = [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5)
                return TestTable2(id: UUID(), parentId: parentId, date: Date(),
                                  name: num % 2 == 0 ? "This is name bind \(num)" : "me",
                                  int: num, doub: Double(num), blob: blob)
            }
        })
    }
    return try getDB(reset: false)
}

@Suite(.serialized)
struct MariaDBTests {

    @Test func connect() throws {
        guard mariaEnabled else { return }
        let mysql = MySQL()
        #expect(mysql.setOption(.MYSQL_OPT_RECONNECT, true))
        #expect(mysql.setOption(.MYSQL_OPT_LOCAL_INFILE))
        #expect(mysql.setOption(.MYSQL_OPT_CONNECT_TIMEOUT, 5))
        let res = mysql.connect(host: testHost, user: testUser, password: testPassword)
        #expect(res)
        let sres = mysql.selectDatabase(named: testSchema)
            || mysql.query(statement: "CREATE SCHEMA `\(testSchema)` DEFAULT CHARACTER SET utf8mb4")
        #expect(sres)
        mysql.close()
    }

    @Test func listDbs1() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        let list = mysql.listDatabases()
        #expect(list.count > 0)
    }

    @Test func listDbs2() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        let list = mysql.listDatabases(wildcard: "information_%")
        #expect(list.count > 0)
    }

    @Test func listTables1() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.selectDatabase(named: "information_schema"))
        let list = mysql.listTables()
        #expect(list.count > 0)
    }

    @Test func listTables2() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.selectDatabase(named: "information_schema"))
        let list = mysql.listTables(wildcard: "INNODB_%")
        #expect(list.count > 0)
    }

    @Test func query1() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS test"))
        #expect(mysql.query(statement: "CREATE TABLE test (id INT, d DOUBLE, s VARCHAR(1024))"), "\(mysql.errorMessage())")
        let list = mysql.listTables(wildcard: "test")
        #expect(list.count > 0)
        for i in 1...10 {
            #expect(mysql.query(statement: "INSERT INTO test (id,d,s) VALUES (\(i),42.9,\"Row \(i)\")"), "\(mysql.errorMessage())")
        }
        #expect(mysql.query(statement: "SELECT id,d,s FROM test"), "\(mysql.errorMessage())")
        guard let results = mysql.storeResults() else { Issue.record("storeResults() failed"); return }
        #expect(results.numRows() == 10)
        var count = 0
        while let _ = results.next() { count += 1 }
        #expect(count == 10)
        results.close()
        #expect(mysql.query(statement: "DROP TABLE test"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "test").count == 0)
    }

    @Test func query2() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS test"))
        #expect(mysql.query(statement: "CREATE TABLE test (id INT, d DOUBLE, s VARCHAR(1024))"), "\(mysql.errorMessage())")
        for i in 1...10 {
            #expect(mysql.query(statement: "INSERT INTO test (id,d,s) VALUES (\(i),42.9,\"Row \(i)\")"), "\(mysql.errorMessage())")
        }
        #expect(mysql.query(statement: "SELECT id,d,s FROM test"), "\(mysql.errorMessage())")
        guard let results = mysql.storeResults() else { Issue.record("storeResults() failed"); return }
        #expect(results.numRows() == 10)
        var count = 0
        results.forEachRow { _ in count += 1 }
        #expect(count == 10)
        results.close()
        #expect(mysql.query(statement: "DROP TABLE test"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "test").count == 0)
    }

    @Test func insertNull() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS test"))
        #expect(mysql.query(statement: "CREATE TABLE test (id INT, d DOUBLE, s VARCHAR(1024))"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "INSERT INTO test (id,d,s) VALUES (1,NULL,\"Row 1\")"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT id,d,s FROM test"), "\(mysql.errorMessage())")
        guard let results = mysql.storeResults() else { Issue.record("storeResults() failed"); return }
        #expect(results.numRows() == 1)
        #expect(results.numFields() == 3)
        results.forEachRow { row in
            #expect(row.count == 3)
            #expect(row[0] == "1")
            #expect(row[1] == nil)
            #expect(row[2] == "Row 1")
        }
        results.close()
        #expect(mysql.query(statement: "DROP TABLE test"), "\(mysql.errorMessage())")
        #expect(mysql.listTables(wildcard: "test").count == 0)
    }

    @Test func queryStmt1() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS all_data_types"))
        let qres = mysql.query(statement: "CREATE TABLE `all_data_types` (`varchar` VARCHAR( 20 ),\n`tinyint` TINYINT,\n`text` TEXT,\n`date` DATE,\n`smallint` SMALLINT,\n`mediumint` MEDIUMINT,\n`int` INT,\n`bigint` BIGINT,\n`float` FLOAT( 10, 2 ),\n`double` DOUBLE,\n`decimal` DECIMAL( 10, 2 ),\n`datetime` DATETIME,\n`timestamp` TIMESTAMP,\n`time` TIME,\n`year` YEAR,\n`char` CHAR( 10 ),\n`tinyblob` TINYBLOB,\n`tinytext` TINYTEXT,\n`blob` BLOB,\n`mediumblob` MEDIUMBLOB,\n`mediumtext` MEDIUMTEXT,\n`longblob` LONGBLOB,\n`longtext` LONGTEXT,\n`enum` ENUM( '1', '2', '3' ),\n`set` SET( '1', '2', '3' ),\n`bool` BOOL,\n`binary` BINARY( 20 ),\n`varbinary` VARBINARY( 20 ) ) ENGINE = MYISAM")
        #expect(qres, "\(mysql.errorMessage())")
        let stmt1 = MySQLStmt(mysql)
        defer { stmt1.close() }
        let prepRes = stmt1.prepare(statement: "INSERT INTO all_data_types VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        #expect(prepRes, "\(stmt1.errorMessage())")
        #expect(stmt1.paramCount() == 28)
        stmt1.bindParam("varchar 20 string")
        stmt1.bindParam(1)
        stmt1.bindParam("text string")
        stmt1.bindParam("2015-10-21")
        stmt1.bindParam(1); stmt1.bindParam(1); stmt1.bindParam(1); stmt1.bindParam(1)
        stmt1.bindParam(1.1); stmt1.bindParam(1.1); stmt1.bindParam(1.1)
        stmt1.bindParam("2015-10-21 12:00:00"); stmt1.bindParam("2015-10-21 12:00:00")
        stmt1.bindParam("03:14:07"); stmt1.bindParam("2015"); stmt1.bindParam("K")
        "BLOB DATA".withCString { p in
            stmt1.bindParam(p, length: 9); stmt1.bindParam("tiny text string")
            stmt1.bindParam(p, length: 9); stmt1.bindParam(p, length: 9)
            stmt1.bindParam("medium text string"); stmt1.bindParam(p, length: 9)
            stmt1.bindParam("long text string"); stmt1.bindParam("1"); stmt1.bindParam("2")
            stmt1.bindParam(1); stmt1.bindParam(0); stmt1.bindParam(1)
            let execRes = stmt1.execute()
            #expect(execRes, "\(stmt1.errorCode()) \(stmt1.errorMessage())")
        }
    }

    @Test func queryStmt2() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS all_data_types"))
        let qres = mysql.query(statement: "CREATE TABLE `all_data_types` (`varchar` VARCHAR( 20 ),\n`tinyint` TINYINT,\n`text` TEXT,\n`date` DATE,\n`smallint` SMALLINT,\n`mediumint` MEDIUMINT,\n`int` INT,\n`bigint` BIGINT,\n`ubigint` BIGINT UNSIGNED,\n`float` FLOAT( 10, 2 ),\n`double` DOUBLE,\n`decimal` DECIMAL( 10, 2 ),\n`datetime` DATETIME,\n`timestamp` TIMESTAMP,\n`time` TIME,\n`year` YEAR,\n`char` CHAR( 10 ),\n`tinyblob` TINYBLOB,\n`tinytext` TINYTEXT,\n`blob` BLOB,\n`mediumblob` MEDIUMBLOB,\n`mediumtext` MEDIUMTEXT,\n`longblob` LONGBLOB,\n`longtext` LONGTEXT,\n`enum` ENUM( '1', '2', '3' ),\n`set` SET( '1', '2', '3' ),\n`bool` BOOL,\n`binary` BINARY( 20 ),\n`varbinary` VARBINARY( 20 ) ) ENGINE = MYISAM")
        #expect(qres, "\(mysql.errorMessage())")
        for _ in 1...2 {
            let stmt1 = MySQLStmt(mysql)
            defer { stmt1.close() }
            let prepRes = stmt1.prepare(statement: "INSERT INTO all_data_types VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
            #expect(prepRes, "\(stmt1.errorMessage())")
            #expect(stmt1.paramCount() == 29)
            stmt1.bindParam("varchar 20 string 👻"); stmt1.bindParam(1)
            stmt1.bindParam("text string"); stmt1.bindParam("2015-10-21")
            stmt1.bindParam(32767); stmt1.bindParam(8388607)
            stmt1.bindParam(2147483647); stmt1.bindParam(9223372036854775807)
            stmt1.bindParam(18446744073709551615 as UInt64)
            stmt1.bindParam(1.1); stmt1.bindParam(1.1); stmt1.bindParam(1.1)
            stmt1.bindParam("2015-10-21 12:00:00"); stmt1.bindParam("2015-10-21 12:00:00")
            stmt1.bindParam("03:14:07"); stmt1.bindParam("2015"); stmt1.bindParam("K")
            "BLOB DATA".withCString { p in
                stmt1.bindParam(p, length: 9); stmt1.bindParam("tiny text string")
                stmt1.bindParam(p, length: 9); stmt1.bindParam(p, length: 9)
                stmt1.bindParam("medium text string"); stmt1.bindParam(p, length: 9)
                stmt1.bindParam("long text string"); stmt1.bindParam("1"); stmt1.bindParam("2")
                stmt1.bindParam(1); stmt1.bindParam(1); stmt1.bindParam(1)
                let execRes = stmt1.execute()
                #expect(execRes, "\(stmt1.errorCode()) \(stmt1.errorMessage())")
            }
        }
        do {
            let stmt1 = MySQLStmt(mysql)
            defer { stmt1.close() }
            let prepRes = stmt1.prepare(statement: "SELECT * FROM all_data_types")
            #expect(prepRes, "\(stmt1.errorMessage())")
            #expect(stmt1.execute(), "\(stmt1.errorMessage())")
            let results = stmt1.results()
            defer { results.close() }
            let ok = results.forEachRow { e in
                #expect(e[0] as? String == "varchar 20 string 👻")
                #expect(e[1] as? Int8 == 1)
                if let estrbuffer = e[2] as? [UInt8], let estr = String(bytes: estrbuffer, encoding: .utf8) {
                    #expect(estr == "text string")
                }
                #expect(e[3] as? String == "2015-10-21")
                #expect(e[4] as? Int16 == 32767)
                #expect(e[5] as? Int32 == 8388607)
                #expect(e[6] as? Int32 == 2147483647)
                #expect(e[7] as? Int64 == 9223372036854775807)
                #expect(e[8] as? UInt64 == 18446744073709551615 as UInt64)
                #expect(e[9] as? Float == 1.1)
                #expect(e[10] as? Double == 1.1)
                #expect(e[11] as? String == "1.10")
                #expect(e[12] as? String == "2015-10-21 12:00:00")
                #expect(e[13] as? String == "2015-10-21 12:00:00")
                #expect(e[14] as? String == "03:14:07")
                #expect(e[15] as? String == "2015")
                #expect(e[16] as? String == "K")
                #expect(UTF8Encoding.encode(bytes: e[17] as! [UInt8]) == "BLOB DATA")
                #expect(UTF8Encoding.encode(bytes: e[18] as! [UInt8]) == "tiny text string")
                #expect(UTF8Encoding.encode(bytes: e[19] as! [UInt8]) == "BLOB DATA")
                #expect(UTF8Encoding.encode(bytes: e[20] as! [UInt8]) == "BLOB DATA")
                #expect(UTF8Encoding.encode(bytes: e[21] as! [UInt8]) == "medium text string")
                #expect(UTF8Encoding.encode(bytes: e[22] as! [UInt8]) == "BLOB DATA")
                #expect(UTF8Encoding.encode(bytes: e[23] as! [UInt8]) == "long text string")
                #expect(e[24] as? String == "1")
                #expect(e[25] as? String == "2")
                #expect(e[26] as? Int8 == 1)
                #expect(e[27] as? String == "1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0")
                #expect(e[28] as? String == "1")
            }
            #expect(ok, "\(stmt1.errorMessage())")
        }
    }

    @Test func serverVersion() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.serverVersion() >= 50627)
    }

    @Test func queryInt() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (-1, 1, -2, 2, -3, 3, -4, 4, -5, 5)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT * FROM int_test"), "\(mysql.errorMessage())")
        if let results = mysql.storeResults() {
            defer { results.close() }
            while let row = results.next() {
                #expect(row[0] == "-1"); #expect(row[1] == "1")
                #expect(row[2] == "-2"); #expect(row[3] == "2")
                #expect(row[4] == "-3"); #expect(row[5] == "3")
                #expect(row[6] == "-4"); #expect(row[7] == "4")
                #expect(row[8] == "-5"); #expect(row[9] == "5")
            }
        }
    }

    @Test func queryIntMin() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (-128, 0, -32768, 0, -8388608, 0, -2147483648, 0, -9223372036854775808, 0)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT * FROM int_test"), "\(mysql.errorMessage())")
        if let results = mysql.storeResults() {
            defer { results.close() }
            while let row = results.next() {
                #expect(row[0] == "-128"); #expect(row[1] == "0")
                #expect(row[2] == "-32768"); #expect(row[3] == "0")
                #expect(row[4] == "-8388608"); #expect(row[5] == "0")
                #expect(row[6] == "-2147483648"); #expect(row[7] == "0")
                #expect(row[8] == "-9223372036854775808"); #expect(row[9] == "0")
            }
        }
    }

    @Test func procedure() throws {
        guard mariaEnabled else { return }
        // procedure tests require stored procedure support — skipped
    }

    @Test func queryIntMax() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (127, 255, 32767, 65535, 8388607, 16777215, 2147483647, 4294967295, 9223372036854775807, 18446744073709551615)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT * FROM int_test"), "\(mysql.errorMessage())")
        if let results = mysql.storeResults() {
            defer { results.close() }
            while let row = results.next() {
                #expect(row[0] == "127"); #expect(row[1] == "255")
                #expect(row[2] == "32767"); #expect(row[3] == "65535")
                #expect(row[4] == "8388607"); #expect(row[5] == "16777215")
                #expect(row[6] == "2147483647"); #expect(row[7] == "4294967295")
                #expect(row[8] == "9223372036854775807"); #expect(row[9] == "18446744073709551615")
            }
        }
    }

    @Test func queryDecimal() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS decimal_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE decimal_test (f FLOAT, fm FLOAT, d DOUBLE, dm DOUBLE, de DECIMAL(2,1), dem DECIMAL(2,1))"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "INSERT INTO decimal_test (f, fm, d, dm, de, dem) VALUES (1.1, -1.1, 2.2, -2.2, 3.3, -3.3)"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "SELECT * FROM decimal_test"), "\(mysql.errorMessage())")
        if let results = mysql.storeResults() {
            defer { results.close() }
            while let row = results.next() {
                #expect(row[0] == "1.1"); #expect(row[1] == "-1.1")
                #expect(row[2] == "2.2"); #expect(row[3] == "-2.2")
                #expect(row[4] == "3.3"); #expect(row[5] == "-3.3")
            }
        }
    }

    @Test func stmtInt() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        let stmt = MySQLStmt(mysql); defer { stmt.close() }
        #expect(stmt.prepare(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"), "\(stmt.errorMessage())")
        stmt.bindParam(-1); stmt.bindParam(1); stmt.bindParam(-2); stmt.bindParam(2)
        stmt.bindParam(-3); stmt.bindParam(3); stmt.bindParam(-4); stmt.bindParam(4)
        stmt.bindParam(-5); stmt.bindParam(5)
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        stmt.reset()
        #expect(stmt.prepare(statement: "SELECT * FROM int_test"), "\(stmt.errorMessage())")
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        let results = stmt.results(); defer { results.close() }
        #expect(results.numRows == 1)
        let ok1 = results.forEachRow { row in
            #expect(row[0] as? Int8 == -1); #expect(row[1] as? UInt8 == 1)
            #expect(row[2] as? Int16 == -2); #expect(row[3] as? UInt16 == 2)
            #expect(row[4] as? Int32 == -3); #expect(row[5] as? UInt32 == 3)
            #expect(row[6] as? Int32 == -4); #expect(row[7] as? UInt32 == 4)
            #expect(row[8] as? Int64 == -5); #expect(row[9] as? UInt64 == 5)
        }
        #expect(ok1)
    }

    @Test func stmtIntMin() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        let stmt = MySQLStmt(mysql); defer { stmt.close() }
        #expect(stmt.prepare(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"), "\(stmt.errorMessage())")
        stmt.bindParam(-128); stmt.bindParam(0); stmt.bindParam(-32768); stmt.bindParam(0)
        stmt.bindParam(-8388608); stmt.bindParam(0); stmt.bindParam(-2147483648); stmt.bindParam(0)
        stmt.bindParam(-9223372036854775808); stmt.bindParam(0)
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        stmt.reset()
        #expect(stmt.prepare(statement: "SELECT * FROM int_test"), "\(stmt.errorMessage())")
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        let results = stmt.results(); defer { results.close() }
        let ok2 = results.forEachRow { row in
            #expect(row[0] as? Int8 == -128); #expect(row[1] as? UInt8 == 0)
            #expect(row[2] as? Int16 == -32768); #expect(row[3] as? UInt16 == 0)
            #expect(row[4] as? Int32 == -8388608); #expect(row[5] as? UInt32 == 0)
            #expect(row[6] as? Int32 == -2147483648); #expect(row[7] as? UInt32 == 0)
            #expect(row[8] as? Int64 == -9223372036854775808); #expect(row[9] as? UInt64 == 0)
        }
        #expect(ok2)
    }

    @Test func stmtIntMax() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS int_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE int_test (a TINYINT, au TINYINT UNSIGNED, b SMALLINT, bu SMALLINT UNSIGNED, c MEDIUMINT, cu MEDIUMINT UNSIGNED, d INT, du INT UNSIGNED, e BIGINT, eu BIGINT UNSIGNED)"), "\(mysql.errorMessage())")
        let stmt = MySQLStmt(mysql); defer { stmt.close() }
        #expect(stmt.prepare(statement: "INSERT INTO int_test (a, au, b, bu, c, cu, d, du, e, eu) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"), "\(stmt.errorMessage())")
        stmt.bindParam(127); stmt.bindParam(255); stmt.bindParam(32767); stmt.bindParam(65535)
        stmt.bindParam(8388607); stmt.bindParam(16777215); stmt.bindParam(2147483647); stmt.bindParam(4294967295)
        stmt.bindParam(9223372036854775807); stmt.bindParam(18446744073709551615 as UInt64)
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        stmt.reset()
        #expect(stmt.prepare(statement: "SELECT * FROM int_test"), "\(stmt.errorMessage())")
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        let results = stmt.results(); defer { results.close() }
        let ok3 = results.forEachRow { row in
            #expect(row[0] as? Int8 == 127); #expect(row[1] as? UInt8 == 255)
            #expect(row[2] as? Int16 == 32767); #expect(row[3] as? UInt16 == 65535)
            #expect(row[4] as? Int32 == 8388607); #expect(row[5] as? UInt32 == 16777215)
            #expect(row[6] as? Int32 == 2147483647); #expect(row[7] as? UInt32 == 4294967295)
            #expect(row[8] as? Int64 == 9223372036854775807); #expect(row[9] as? UInt64 == 18446744073709551615)
        }
        #expect(ok3)
    }

    @Test func stmtDecimal() throws {
        guard mariaEnabled else { return }
        let mysql = makeMySQL()
        #expect(mysql.query(statement: "DROP TABLE IF EXISTS decimal_test"), "\(mysql.errorMessage())")
        #expect(mysql.query(statement: "CREATE TABLE decimal_test (f FLOAT, fm FLOAT, d DOUBLE, dm DOUBLE, de DECIMAL(2,1), dem DECIMAL(2,1))"), "\(mysql.errorMessage())")
        let stmt = MySQLStmt(mysql); defer { stmt.close() }
        #expect(stmt.prepare(statement: "INSERT INTO decimal_test (f, fm, d, dm, de, dem) VALUES (?, ?, ?, ?, ?, ?)"), "\(stmt.errorMessage())")
        stmt.bindParam(1.1); stmt.bindParam(-1.1); stmt.bindParam(2.2)
        stmt.bindParam(-2.2); stmt.bindParam(3.3); stmt.bindParam(-3.3)
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        stmt.reset()
        #expect(stmt.prepare(statement: "SELECT * FROM decimal_test"), "\(stmt.errorMessage())")
        #expect(stmt.execute(), "\(stmt.errorMessage())")
        let results = stmt.results(); defer { results.close() }
        let ok4 = results.forEachRow { row in
            #expect(row[0] as? Float == 1.1); #expect(row[1] as? Float == -1.1)
            #expect(row[2] as? Double == 2.2); #expect(row[3] as? Double == -2.2)
            #expect(row[4] as? String == "3.3"); #expect(row[5] as? String == "-3.3")
        }
        #expect(ok4)
    }

    // CRUD tests

    @Test func create1() throws {
        guard mariaEnabled else { return }
        let db = try getDB()
        try db.create(TestTable1.self, policy: .dropTable)
        do { let t2 = db.table(TestTable2.self); try t2.index(\.parentId) }
        let t1 = db.table(TestTable1.self)
        let subId = UUID()
        try db.transaction {
            let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
            try t1.insert(newOne)
            let newSub1 = TestTable2(id: subId, parentId: 2000, date: Date(), name: "Me")
            let newSub2 = TestTable2(id: UUID(), parentId: 2000, date: Date(), name: "Not Me")
            try db.table(TestTable2.self).insert([newSub1, newSub2])
        }
        let j21 = try t1.join(\.subTables, on: \.id, equals: \.parentId)
        let j2 = j21.where(\TestTable1.id == 2000 && \TestTable2.name == "Me")
        let j3 = j21.where(\TestTable1.id > 20 && !(\TestTable1.name == "Me" || \TestTable1.name == "You"))
        #expect(try j3.count() == 1)
        try db.transaction {
            let j2a = try j2.select().map { $0 }
            #expect(try j2.count() == 1)
            #expect(j2a.count == 1)
            guard j2a.count == 1 else { return }
            let obj = j2a[0]
            #expect(obj.id == 2000)
            #expect(obj.subTables != nil)
            let subTables = obj.subTables!
            #expect(subTables.count == 1)
            #expect(subTables[0].id == subId)
        }
        try db.create(TestTable1.self)
        let j2a = try j2.select().map { $0 }
        #expect(try j2.count() == 1)
        #expect(j2a[0].id == 2000)
        try db.create(TestTable1.self, policy: .dropTable)
        #expect(try j2.select().map { $0 }.count == 0)
    }

    @Test func create2() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        try db.create(TestTable1.self, primaryKey: \.id, policy: .dropTable)
        do { let t2 = db.table(TestTable2.self); try t2.index(\.parentId, \.date) }
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne)
        let j2 = try t1.where(\TestTable1.id == 2000).select()
        #expect(j2.map { $0 }.count == 1)
        #expect(j2.map { $0 }[0].id == 2000)
        try db.create(TestTable1.self)
        #expect(j2.map { $0 }.count == 1)
        try db.create(TestTable1.self, policy: .dropTable)
        #expect(j2.map { $0 }.count == 0)
    }

    @Test func create3() throws {
        guard mariaEnabled else { return }
        struct FakeTestTable1: Codable, TableNameProvider {
            enum CodingKeys: String, CodingKey { case id, name, double = "doub", double2 = "doub2", blob, subTables }
            static let tableName = "test_table_1"
            let id: Int; let name: String?; let double2: Double?; let double: Double?; let blob: [UInt8]?; let subTables: [TestTable2]?
        }
        let db = try getTestDB()
        try db.create(TestTable1.self, policy: [.dropTable, .shallow])
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne)
        try db.create(FakeTestTable1.self, policy: [.reconcileTable, .shallow])
        let j2 = try db.table(FakeTestTable1.self).where(\FakeTestTable1.id == 2000).select()
        #expect(j2.map { $0 }.count == 1)
        #expect(j2.map { $0 }[0].id == 2000)
    }

    @Test func selectAll() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        for row in try db.table(TestTable1.self).select() {
            #expect(row.subTables == nil)
        }
    }

    @Test func selectIn() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let table = db.table(TestTable1.self)
        #expect(try table.where(\TestTable1.id ~ [2, 4]).count() == 2)
        #expect(try table.where(\TestTable1.id !~ [2, 4]).count() == 3)
    }

    @Test func selectLikeString() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let table = db.table(TestTable2.self)
        #expect(try table.where(\TestTable2.name %=% "me").count() == 25)
        #expect(try table.where(\TestTable2.name =% "me").count() == 15)
        #expect(try table.where(\TestTable2.name %= "me").count() == 15)
        #expect(try table.where(\TestTable2.name %!=% "me").count() == 0)
        #expect(try table.where(\TestTable2.name !=% "me").count() == 10)
        #expect(try table.where(\TestTable2.name %!= "me").count() == 10)
    }

    @Test func selectJoin() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let j2 = try db.table(TestTable1.self)
            .order(by: \TestTable1.name)
            .join(\.subTables, on: \.id, equals: \.parentId)
            .order(by: \.id)
            .where(\TestTable2.name == "me")
        let j2c = try j2.count()
        let j2a = try j2.select().map { $0 }
        #expect(j2c != 0)
        #expect(j2c == j2a.count)
        j2a.forEach { row in #expect(!(row.subTables?.isEmpty ?? true)) }
    }

    @Test func insert1() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New ` One", integer: 40)
        try t1.insert(newOne)
        let j1 = t1.where(\TestTable1.id == newOne.id)
        let j2 = try j1.select().map { $0 }
        #expect(try j1.count() == 1)
        #expect(j2[0].id == 2000)
        #expect(j2[0].name == "New ` One")
    }

    @Test func insert2() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne, ignoreKeys: \TestTable1.integer)
        let j1 = t1.where(\TestTable1.id == newOne.id)
        let j2 = try j1.select().map { $0 }
        #expect(try j1.count() == 1)
        #expect(j2[0].id == 2000)
        #expect(j2[0].integer == nil)
    }

    @Test func insert3() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        let newTwo = TestTable1(id: 2001, name: "New One", integer: 40)
        try t1.insert([newOne, newTwo], setKeys: \TestTable1.id, \TestTable1.integer)
        let j1 = t1.where(\TestTable1.id == newOne.id)
        let j2 = try j1.select().map { $0 }
        #expect(try j1.count() == 1)
        #expect(j2[0].id == 2000)
        #expect(j2[0].integer == 40)
        #expect(j2[0].name == nil)
    }

    @Test func update() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        let newId: Int = try db.transaction {
            try db.table(TestTable1.self).insert(newOne)
            let newOne2 = TestTable1(id: 2000, name: "New👻One Updated", integer: 41)
            try db.table(TestTable1.self).where(\TestTable1.id == newOne.id).update(newOne2, setKeys: \.name)
            return newOne2.id
        }
        let j2 = try db.table(TestTable1.self).where(\TestTable1.id == newId).select().map { $0 }
        #expect(j2.count == 1)
        #expect(j2[0].id == 2000)
        #expect(j2[0].name == "New👻One Updated")
        #expect(j2[0].integer == 40)
    }

    @Test func delete() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        let newOne = TestTable1(id: 2000, name: "New One", integer: 40)
        try t1.insert(newOne)
        let query = t1.where(\TestTable1.id == newOne.id)
        #expect(try query.select().map { $0 }.count == 1)
        try query.delete()
        #expect(try query.select().map { $0 }.count == 0)
    }

    @Test func selectLimit() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        #expect(try db.table(TestTable1.self).limit(3, skip: 2).count() == 3)
    }

    @Test func selectLimitWhere() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let j2 = db.table(TestTable1.self).limit(3).where(\TestTable1.id > 3)
        #expect(try j2.count() == 2)
        #expect(try j2.select().map { $0 }.count == 2)
    }

    @Test func selectOrderLimitWhere() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let j2 = db.table(TestTable1.self).order(by: \TestTable1.id).limit(3).where(\TestTable1.id > 3)
        #expect(try j2.count() == 2)
        #expect(try j2.select().map { $0 }.count == 2)
    }

    @Test func selectWhereNULL() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let t1 = db.table(TestTable1.self)
        #expect(try t1.where(\TestTable1.blob == nil).count() > 0)
        #expect(try t1.where(\TestTable1.blob != nil).count() > 0)
        CRUDLogging.flush()
    }

    @Test func personThing() throws {
        guard mariaEnabled else { return }
        struct PhoneNumber: Codable { let personId: UUID; let planetCode: Int; let number: String }
        struct Person: Codable { let id: UUID; let firstName: String; let lastName: String; let phoneNumbers: [PhoneNumber]? }
        let db = try getTestDB()
        try db.create(Person.self, policy: .reconcileTable)
        let personTable = db.table(Person.self)
        let numbersTable = db.table(PhoneNumber.self)
        try numbersTable.index(\.personId)
        let owen = Person(id: UUID(), firstName: "Owen", lastName: "Lars", phoneNumbers: nil)
        let beru = Person(id: UUID(), firstName: "Beru", lastName: "Lars", phoneNumbers: nil)
        try personTable.insert([owen, beru])
        try numbersTable.insert([
            PhoneNumber(personId: owen.id, planetCode: 12, number: "555-555-1212"),
            PhoneNumber(personId: owen.id, planetCode: 15, number: "555-555-2222"),
            PhoneNumber(personId: beru.id, planetCode: 12, number: "555-555-1212")])
        let query = try personTable.order(by: \.lastName, \.firstName)
            .join(\.phoneNumbers, on: \.id, equals: \.personId)
            .order(descending: \.planetCode)
            .where(\Person.lastName == "Lars" && \PhoneNumber.planetCode == 12)
            .select()
        for user in query {
            guard let numbers = user.phoneNumbers else { continue }
            for number in numbers { _ = number.number }
        }
        CRUDLogging.flush()
    }

    @Test func standardJoin() throws {
        guard mariaEnabled else { return }
        struct Parent: Codable { let id: Int; let children: [Child]?; init(id i: Int) { id = i; children = nil } }
        struct Child: Codable { let id: Int; let parentId: Int }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Parent.self, policy: [.shallow, .dropTable]).insert(Parent(id: 1))
            try db.create(Child.self, policy: [.shallow, .dropTable]).insert([Child(id: 1, parentId: 1), Child(id: 2, parentId: 1), Child(id: 3, parentId: 1)])
        }
        let join = try db.table(Parent.self).join(\.children, on: \.id, equals: \.parentId).where(\Parent.id == 1)
        guard let parent = try join.first() else { Issue.record("Failed to find parent id: 1"); return }
        guard let children = parent.children else { Issue.record("Parent had no children"); return }
        #expect(children.count == 3)
        for child in children { #expect(child.parentId == parent.id) }
        CRUDLogging.flush()
    }

    @Test func junctionJoin() throws {
        guard mariaEnabled else { return }
        struct Student: Codable { let id: Int; let classes: [Class]?; init(id i: Int) { id = i; classes = nil } }
        struct Class: Codable { let id: Int; let students: [Student]?; init(id i: Int) { id = i; students = nil } }
        struct StudentClasses: Codable { let studentId: Int; let classId: Int }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Student.self, policy: [.dropTable, .shallow]).insert(Student(id: 1))
            try db.create(Class.self, policy: [.dropTable, .shallow]).insert([Class(id: 1), Class(id: 2), Class(id: 3)])
            try db.create(StudentClasses.self, policy: [.dropTable, .shallow]).insert([
                StudentClasses(studentId: 1, classId: 1), StudentClasses(studentId: 1, classId: 2), StudentClasses(studentId: 1, classId: 3)])
        }
        let join = try db.table(Student.self).join(\.classes, with: StudentClasses.self, on: \.id, equals: \.studentId, and: \.id, is: \.classId).where(\Student.id == 1)
        guard let student = try join.first() else { Issue.record("Failed to find student id: 1"); return }
        guard let classes = student.classes else { Issue.record("Student had no classes"); return }
        #expect(classes.count == 3)
        for aClass in classes {
            let classJoin = try db.table(Class.self).join(\.students, with: StudentClasses.self, on: \.id, equals: \.classId, and: \.id, is: \.studentId).where(\Class.id == aClass.id)
            guard let found = try classJoin.first() else { Issue.record("Class with no students"); continue }
            #expect(found.students?.first(where: { $0.id == student.id }) != nil)
        }
        CRUDLogging.flush()
    }

    @Test func selfJoin() throws {
        guard mariaEnabled else { return }
        struct Me: Codable { let id: Int; let parentId: Int; let mes: [Me]?; init(id i: Int, parentId p: Int) { id = i; parentId = p; mes = nil } }
        let db = try getTestDB()
        _ = try db.transaction {
            try db.create(Me.self, policy: .dropTable).insert([Me(id: 1, parentId: 0), Me(id: 2, parentId: 1), Me(id: 3, parentId: 1), Me(id: 4, parentId: 1), Me(id: 5, parentId: 1)])
        }
        let join = try db.table(Me.self).join(\.mes, on: \.id, equals: \.parentId).where(\Me.id == 1)
        guard let me = try join.first() else { Issue.record("Unable to find me."); return }
        guard let mes = me.mes else { Issue.record("Unable to find meesa."); return }
        #expect(mes.count == 4)
    }

    @Test func selfJunctionJoin() throws {
        guard mariaEnabled else { return }
        struct Me: Codable { let id: Int; let us: [Me]?; init(id i: Int) { id = i; us = nil } }
        struct Us: Codable { let you: Int; let them: Int }
        let db = try getTestDB()
        try db.transaction {
            try db.create(Me.self, policy: .dropTable).insert((1...5).map { .init(id: $0) })
            try db.create(Us.self, policy: .dropTable).insert((2...5).map { .init(you: 1, them: $0) })
        }
        let join = try db.table(Me.self).join(\.us, with: Us.self, on: \.id, equals: \.you, and: \.id, is: \.them).where(\Me.id == 1)
        guard let me = try join.first() else { Issue.record("Unable to find me."); return }
        guard let us = me.us else { Issue.record("Unable to find us."); return }
        #expect(us.count == 4)
    }

    @Test func codableProperty() throws {
        guard mariaEnabled else { return }
        struct Sub: Codable { let id: Int }
        struct Top: Codable { let id: Int; let sub: Sub? }
        let db = try getTestDB()
        try db.create(Sub.self); try db.create(Top.self)
        let t1 = Top(id: 1, sub: Sub(id: 1))
        try db.table(Top.self).insert(t1)
        guard let top = try db.table(Top.self).where(\Top.id == 1).first() else { Issue.record("Unable to find top."); return }
        #expect(top.sub?.id == t1.sub?.id)
    }

    @Test func badDecoding() throws {
        guard mariaEnabled else { return }
        struct Top: Codable, TableNameProvider { static let tableName = "Top"; let id: Int }
        struct NTop: Codable, TableNameProvider { static let tableName = "Top"; let nid: Int }
        let db = try getTestDB()
        try db.create(Top.self, policy: .dropTable)
        try db.table(Top.self).insert(Top(id: 1))
        do {
            _ = try db.table(NTop.self).first()
            Issue.record("Should not have a valid object.")
        } catch {}
    }

    @Test func allPrimTypes1() throws {
        guard mariaEnabled else { return }
        struct AllTypes: Codable {
            let int: Int; let uint: UInt; let int64: Int64; let uint64: UInt64
            let int32: Int32?; let uint32: UInt32?; let int16: Int16; let uint16: UInt16
            let int8: Int8?; let uint8: UInt8?; let double: Double; let float: Float
            let string: String; let bytes: [Int8]; let ubytes: [UInt8]?; let b: Bool
        }
        do {
            let db = try getTestDB()
            try db.create(AllTypes.self, policy: .dropTable)
            let model = AllTypes(int: 1, uint: 2, int64: 3, uint64: 4, int32: 5, uint32: 6, int16: 7, uint16: 8, int8: 9, uint8: 10, double: 11, float: 12, string: "13", bytes: [1, 4], ubytes: [1, 4], b: true)
            try db.table(AllTypes.self).insert(model)
            guard let f = try db.table(AllTypes.self).where(\AllTypes.int == 1).first() else { Issue.record("Nil result."); return }
            #expect(model.int == f.int); #expect(model.uint == f.uint); #expect(model.int64 == f.int64); #expect(model.uint64 == f.uint64)
            #expect(model.int32 == f.int32); #expect(model.uint32 == f.uint32); #expect(model.int16 == f.int16); #expect(model.uint16 == f.uint16)
            #expect(model.int8 == f.int8); #expect(model.uint8 == f.uint8); #expect(model.double == f.double); #expect(model.float == f.float)
            #expect(model.string == f.string); #expect(model.bytes == f.bytes); #expect(model.ubytes! == f.ubytes!); #expect(model.b == f.b)
        }
        do {
            let db = try getTestDB()
            try db.create(AllTypes.self, policy: .dropTable)
            let model = AllTypes(int: 1, uint: 2, int64: -3, uint64: 4, int32: nil, uint32: nil, int16: -7, uint16: 8, int8: nil, uint8: nil, double: -11, float: -12, string: "13", bytes: [1, 4], ubytes: nil, b: true)
            try db.table(AllTypes.self).insert(model)
            guard let f = try db.table(AllTypes.self).where(\AllTypes.int == 1).first() else { Issue.record("Nil result."); return }
            #expect(model.int == f.int); #expect(model.uint == f.uint); #expect(model.int64 == f.int64); #expect(model.uint64 == f.uint64)
            #expect(model.int32 == f.int32); #expect(model.uint32 == f.uint32); #expect(model.int16 == f.int16); #expect(model.uint16 == f.uint16)
            #expect(model.int8 == f.int8); #expect(model.uint8 == f.uint8); #expect(model.double == f.double); #expect(model.float == f.float)
            #expect(model.string == f.string); #expect(model.bytes == f.bytes); #expect(f.ubytes == nil); #expect(model.b == f.b)
        }
    }

    @Test func allPrimTypes2() throws {
        guard mariaEnabled else { return }
        struct AllTypes2: Codable {
            func equals(rhs: AllTypes2) -> Bool {
                guard int == rhs.int && uint == rhs.uint && int64 == rhs.int64 && uint64 == rhs.uint64 &&
                      int32 == rhs.int32 && uint32 == rhs.uint32 && int16 == rhs.int16 && uint16 == rhs.uint16 &&
                      int8 == rhs.int8 && uint8 == rhs.uint8 && double == rhs.double && float == rhs.float &&
                      string == rhs.string && b == rhs.b else { return false }
                guard (bytes == nil) == (rhs.bytes == nil) && (ubytes == nil) == (rhs.ubytes == nil) else { return false }
                if let lhsb = bytes { guard lhsb == rhs.bytes! else { return false } }
                if let lhsb = ubytes { guard lhsb == rhs.ubytes! else { return false } }
                return true
            }
            let int: Int?; let uint: UInt?; let int64: Int64?; let uint64: UInt64?
            let int32: Int32?; let uint32: UInt32?; let int16: Int16?; let uint16: UInt16?
            let int8: Int8?; let uint8: UInt8?; let double: Double?; let float: Float?
            let string: String?; let bytes: [Int8]?; let ubytes: [UInt8]?; let b: Bool?
        }
        let db = try getTestDB()
        try db.create(AllTypes2.self, policy: .dropTable)
        let model = AllTypes2(int: 1, uint: 2, int64: -3, uint64: 4, int32: 5, uint32: 6, int16: 7, uint16: 8, int8: 9, uint8: 10, double: 11.2, float: 12.3, string: "13", bytes: [1, 4], ubytes: [1, 4], b: true)
        try db.table(AllTypes2.self).insert(model)
        do {
            guard let f = try db.table(AllTypes2.self).where(\AllTypes2.int == 1 && \AllTypes2.uint == 2 && \AllTypes2.int64 == -3).first() else { Issue.record("Nil result."); return }
            #expect(model.equals(rhs: f))
            #expect(try db.table(AllTypes2.self).where(\AllTypes2.int != 1 && \AllTypes2.uint != 2 && \AllTypes2.int64 != -3).count() == 0)
        }
        do {
            guard let f = try db.table(AllTypes2.self).where(\AllTypes2.uint64 == 4 && \AllTypes2.int32 == 5 && \AllTypes2.uint32 == 6).first() else { Issue.record("Nil result."); return }
            #expect(model.equals(rhs: f))
        }
        do {
            guard let f = try db.table(AllTypes2.self).where(\AllTypes2.int16 == 7 && \AllTypes2.uint16 == 8 && \AllTypes2.int8 == 9 && \AllTypes2.uint8 == 10).first() else { Issue.record("Nil result."); return }
            #expect(model.equals(rhs: f))
        }
        do {
            guard let f = try db.table(AllTypes2.self).where(\AllTypes2.double == 11.2 && \AllTypes2.float == Float(12.3) && \AllTypes2.string == "13").first() else { Issue.record("Nil result."); return }
            #expect(model.equals(rhs: f))
        }
        do {
            guard let f = try db.table(AllTypes2.self).where(\AllTypes2.bytes == [1, 4] as [Int8] && \AllTypes2.ubytes == [1, 4] as [UInt8] && \AllTypes2.b == true).first() else { Issue.record("Nil result."); return }
            #expect(model.equals(rhs: f))
        }
    }

    @Test func bespokeSQL() throws {
        guard mariaEnabled else { return }
        let db = try getTestDB()
        let r1 = try db.sql("SELECT * FROM \(TestTable1.CRUDTableName) WHERE id = 2", TestTable1.self)
        #expect(r1.count == 1)
        let r2 = try db.sql("SELECT * FROM \(TestTable1.CRUDTableName)", TestTable1.self)
        #expect(r2.count == 5)
    }

    @Test func url() throws {
        guard mariaEnabled else { return }
        struct TableWithURL: Codable { let id: Int; let url: URL }
        let db = try getTestDB()
        try db.create(TableWithURL.self)
        let t1 = db.table(TableWithURL.self)
        let newOne = TableWithURL(id: 2000, url: URL(string: "http://localhost/")!)
        try t1.insert(newOne)
        let j1 = t1.where(\TableWithURL.id == newOne.id)
        let j2 = try j1.select().map { $0 }
        #expect(try j1.count() == 1)
        #expect(j2[0].id == 2000)
        #expect(j2[0].url.absoluteString == "http://localhost/")
    }

    @Test func lastInsertId() throws {
        guard mariaEnabled else { return }
        struct ReturningItem: Codable, Equatable {
            let id: UInt64?; var def: Int?
            init(id: UInt64, def: Int? = nil) { self.id = id; self.def = def }
        }
        let db = try getTestDB()
        try db.sql("DROP TABLE IF EXISTS \(ReturningItem.CRUDTableName)")
        try db.sql("CREATE TABLE \(ReturningItem.CRUDTableName) (id INT PRIMARY KEY AUTO_INCREMENT, def INT DEFAULT 42)")
        let table = db.table(ReturningItem.self)
        let id = try table.insert(ReturningItem(id: 0, def: 0), ignoreKeys: \ReturningItem.id).lastInsertId()
        #expect(id == 1)
    }

    @Test func emptyInsert() throws {
        guard mariaEnabled else { return }
        struct ReturningItem: Codable, Equatable {
            let id: Int?; var def: Int?
            init(id: Int, def: Int? = nil) { self.id = id; self.def = def }
        }
        let db = try getTestDB()
        try db.sql("DROP TABLE IF EXISTS \(ReturningItem.CRUDTableName)")
        try db.sql("CREATE TABLE \(ReturningItem.CRUDTableName) (id INT PRIMARY KEY AUTO_INCREMENT, def INT DEFAULT 42)")
        let table = db.table(ReturningItem.self)
        let id = try table.insert(ReturningItem(id: 0, def: 0), ignoreKeys: \ReturningItem.id, \ReturningItem.def).lastInsertId()
        #expect(id == 1)
    }
}
