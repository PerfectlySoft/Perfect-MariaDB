# Perfect - MariaDB Connector

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache--2.0-lightgrey.svg?style=flat" alt="License Apache 2.0"></a>
</p>

A Swift wrapper around the MariaDB client library (libmariadb), enabling access to MariaDB/MySQL
database servers, with a [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) backend so
CRUD's declarative model/query API can target a MariaDB or MySQL server.

**Modernized for Swift 6**: `swiftLanguageMode(.v6)` on all targets, Sendable/`@unchecked Sendable`
annotations throughout for strict concurrency (this remains a fully synchronous wrapper around the
blocking C `mysql_*` API — there is no async/await here; thread-safety around `MySQL`/`MySQLStmt`
instances is the caller's responsibility), deprecated API replacements, and a migration of the test
suite from XCTest to Swift Testing.

**Status:** real, working, tested infrastructure — staged as an alternative database backend
alongside [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL), for teams that want a
MariaDB target rather than not-yet-in-use or dead code.

The pre-Swift-6 version of this package is preserved on the [`legacy`](../../tree/legacy) branch.

## Requirements

- Swift 6.2 or newer (`swift-tools-version: 6.2`, Swift 6 language mode).
- macOS 12 or newer, or Linux. CI builds and tests on macOS (Xcode 26.0.1 and 26.6) and on Ubuntu 24.04
  (Swift 6.2 and 6.4), with the Linux jobs running the live tests against MariaDB 11.8 and MySQL 8.4.
- MariaDB Connector/C (libmariadb). It talks to both MariaDB and MySQL servers.
- [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) 3.0.0 or newer, which SwiftPM fetches for you.

### macOS

```bash
brew install mariadb-connector-c
```

Homebrew installs it keg-only (it conflicts with the `mariadb` formula), so it isn't linked into `/opt/homebrew`.
SwiftPM in Swift 6.4 finds it through the package's Homebrew provider. With older toolchains (seen with Swift 6.2 in
Xcode 26.3), point pkg-config at it, or the build fails with `'mysql.h' file not found`:

```bash
export PKG_CONFIG_PATH="$(brew --prefix mariadb-connector-c)/lib/pkgconfig"
```

Having Homebrew's `mysql-client` installed as well is fine: the package links `libmariadb` only.

### Linux

```bash
sudo apt-get install pkg-config libmariadb-dev
```

To check that pkg-config finds the library:

```bash
pkg-config libmariadb --cflags --libs
```

## Building

Add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-MariaDB.git", from: "4.0.0"),
    .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "3.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "PerfectMariaDB", package: "Perfect-MariaDB"),
            .product(name: "PerfectCRUD", package: "Perfect-CRUD"),
        ]
    ),
]
```

The library product is named `PerfectMariaDB`, matching `PerfectMySQL` and `PerfectPostgreSQL`; the module is still
imported as `MariaDB`.

Import required libraries:
```swift
import MariaDB
import PerfectCRUD
```

Perfect-MariaDB implements the Perfect-CRUD protocol via `MySQLDatabaseConfiguration` (see `Sources/MariaDB/MySQLCRUD.swift`), letting Perfect-CRUD's declarative model/query API target a MariaDB/MySQL server. See [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) for the CRUD API itself.

Note: the source files retain their original `MySQLCRUD.swift`/`MySQLStmt.swift` naming from this package's shared lineage with [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) — MariaDB is wire-compatible with the MySQL client protocol, and the two packages are separate, independently-buildable connectors in this ecosystem.

### Dynamic queries

Perfect-CRUD's Dynamic API (`select(_: DynamicQuery)`, `mutate(_:)`, `execute(_: DynamicSQL)`) works with this
connector. Integer columns read as `.int` or `.uint` (unsigned columns), FLOAT/DOUBLE as `.double`, binary values as
`.bytes`, and everything else, including DECIMAL and date/time columns, as `.string`. Column names are matched ignoring
case; when a result has several columns whose names differ only by case, or not at all (`p.id, c.id` in a join), the
row keeps the first, so alias the others. `affectedRows` and `insertedID` are reported; a statement that returns rows
(SELECT, CALL, MariaDB's `INSERT ... RETURNING`) reports its row count and no insert ID. A prepared statement holds one
statement, so `DynamicSQL` text with several statements fails as a whole, unless it starts with a statement that runs
unprepared (such as `BEGIN`, or upper-case `CREATE`) on a connection opened with `CLIENT_MULTI_STATEMENTS`, in which
case every statement runs and an error in any of them is thrown.

Limits: an inserted ID above `Int64.max` (BIGINT UNSIGNED) is reported as nil; an UPDATE that changes nothing reports
0 affected rows (the server counts changed rows, not matched ones); `TINYINT(1)` reads as `.int`, not `.bool`; `YEAR` reads as `.string`; statements that run
unprepared (`BEGIN`, `SAVEPOINT`, `LOCK`, upper-case `CREATE`/`DROP`/`ALTER` and the like) report 0 affected rows; and
only the first result set of a CALL that returns several is visible.

### TLS

Set `MYSQL_OPT_SSL_MODE` before connecting, using MySQL's `SSL_MODE_*` values: 1 = DISABLED, 2 = PREFERRED,
3 = REQUIRED, 4 = VERIFY_CA, 5 = VERIFY_IDENTITY. MariaDB Connector/C has no such option, so the modes are mapped onto
`MYSQL_OPT_SSL_ENFORCE` and `MYSQL_OPT_SSL_VERIFY_SERVER_CERT`:

```swift
let mysql = MySQL()
mysql.setOption(.MYSQL_OPT_SSL_CA, "/path/to/ca.pem")
guard mysql.setOption(.MYSQL_OPT_SSL_MODE, 5) else { fatalError("SSL mode not supported") }
```

- **REQUIRED** is checked only after authenticating: Connector/C doesn't refuse a server without TLS, so `connect()`
  closes the plaintext connection and fails with error 2026 afterwards. Someone able to tamper with the connection can
  capture the authentication exchange (or the password, if the server asks for `mysql_clear_password`). Use
  VERIFY_IDENTITY with `MYSQL_OPT_SSL_CA`, which fails before authenticating. REQUIRED also turns off
  `MYSQL_OPT_RECONNECT`, since a reconnect could fall back to plaintext.
- **VERIFY_CA** also checks the host name. Connector/C 3.4 checks neither the host name nor, without
  `MYSQL_OPT_SSL_CA`, the CA on local (loopback or socket) connections.
- **DISABLED** still uses TLS if any `MYSQL_OPT_SSL_*` file or cipher option is set.

Connector/C 3.4 (Homebrew's current version) has stricter defaults when `MYSQL_OPT_SSL_MODE` isn't set. It refuses a
server without TLS ("SSL is required, but the server does not support it"), even on 127.0.0.1; set DISABLED or
PREFERRED to allow one. On connections that aren't local it also verifies the server certificate, so a remote server
with a self-signed certificate is refused unless you pass its CA with `MYSQL_OPT_SSL_CA` or choose PREFERRED/REQUIRED,
which don't verify. Against MariaDB 11.4 and newer, with a password, it can instead verify the server's self-signed
certificate through a fingerprint derived from the password. Connector/C 3.3 (Ubuntu 24.04's `libmariadb-dev`) does none
of this.

## Migrating from 3.x

The previous release was 3.0.4 (2020). 4.0.0 is a Swift 6 rewrite on Perfect-CRUD 3; see Perfect-CRUD's own
release notes for its changes.

- **Toolchain and platforms:** Swift 6.2 or newer and macOS 12 or newer. On macOS with a toolchain older than Swift
  6.4, set `PKG_CONFIG_PATH` as described above.
- **Product name:** depend on `.product(name: "PerfectMariaDB", package: "Perfect-MariaDB")` instead of `"MariaDB"`.
  `import MariaDB` is unchanged.
- **Binary values are bytes:** through `MySQLStmt`, BINARY, VARBINARY, BIT and GEOMETRY values, binary expressions such
  as `CAST(x AS BINARY)` or `UNHEX(...)`, and every string column after `SET NAMES binary` are `[UInt8]`, not `String`.
  Use `String(decoding: bytes, as: UTF8.self)`, or `CAST(... AS CHAR)` in SQL. CRUD models with `String`, `UUID`,
  `Date` or `URL` properties over such columns still decode.
- **Text isn't truncated:** values with invalid UTF-8 used to stop at the first bad byte; they now come back in full,
  with U+FFFD in place of each invalid sequence. `MySQL.Results` gains `nextBytes()`, `forEachRowBytes(callback:)`
  and `fieldIsBinary(at:)` for exact bytes.
- **Statements the server can't prepare run directly,** so Perfect-CRUD's nested transactions (`SAVEPOINT`) and
  `LOCK`/`UNLOCK TABLES` work against MySQL servers. A statement sent this way that returns rows throws.
- **`.reconcileTable`** no longer drops and re-adds columns whose names have uppercase letters (it lost their data),
  adds the FOREIGN KEY constraint of a `@ForeignKey` column it adds (the ALTER fails if existing rows violate it), and
  drops a removed `@ForeignKey` column's constraint with the column.
- **`create()`** creates a table before the sub-tables that reference it, and `.dropTable` drops them in reverse.
- **Errors while reading rows throw:** an error the server reports partway through a result (for example 1242, a
  subquery returning more than one row) used to crash the process inside libmariadb. Perfect-CRUD queries now throw
  `MySQLCRUDError`, and `MySQLStmt.Results` has new `failed`, `errorCode` and `errorMessage` properties (its `next()`
  returns nil and `forEachRow` returns false after a failure).
- **DECIMAL decodes into `Double` and `Float`:** such properties over a DECIMAL column used to read 0.0; they now read
  the value, and text that doesn't parse throws.
- **Dates are read as UTC:** Perfect-CRUD has always written `Date` values as UTC text, but 3.x parsed them in the
  process's local time zone, so outside UTC they came back shifted by the UTC offset, and a row whose UTC time fell in
  a local daylight-saving gap was silently dropped. Dates are now parsed as UTC, and `DATETIME(6)` fractions and `DATE`
  values are read too (they used to drop the row). Rows written through Perfect-CRUD read back correctly with no
  migration. What does shift: apps that compensated for the old offset by hand, and local-time values written outside
  Perfect-CRUD, such as `NOW()` on a server whose time zone isn't UTC, or `TIMESTAMP` columns read in a non-UTC session
  `time_zone` (run the connection in UTC, e.g. `SET time_zone = '+00:00'`, if you need those to line up). The zero
  date (`0000-00-00`) reads as nil for an optional `Date`; for a non-optional one it's an error, which Perfect-CRUD's
  `select()` currently skips the row on. Dates use the proleptic Gregorian calendar, as the server does, so
  1582-10-05...14 parse and older dates are no longer 10 or more days off; fractions stay inside their second, and
  writing truncates to whole seconds (so `9999-12-31 23:59:59.999999` no longer becomes year 10000).
- **CALL rows are readable:** `db.sql("CALL p(?)", bindings: ..., T.self)` and Dynamic queries return the procedure's
  rows (in 3.x every column read as missing). Only the first result set is read; the others are discarded, so the
  connection stays in sync. If a later statement in the procedure fails, the typed and Dynamic calls throw. An untyped
  `db.sql("CALL p()")` can't report such an error, because Perfect-CRUD only starts the statement there; read the rows
  with a type (or use `execute(DynamicSQL)`) when the procedure can fail after its first result set.
- **`MySQLOpt` has a new case,** `MYSQL_OPT_SSL_MODE`, so an exhaustive `switch` over `MySQLOpt` needs a case for it.
- **`listTables` / `listDatabases`** escape their wildcard, and under big5, cp932, gbk, gb18030 or sjis refuse (return
  `[]` for) a wildcard with a non-ASCII byte and a `'` or `\`, which escaping can't make safe there.
- **`[Int8]` properties** read negative bytes instead of trapping (writing them needs Perfect-CRUD 3.0.1).
- **`connect()`** always passes `CLIENT_REMEMBER_OPTIONS`, so options survive a failed connection attempt.

## Further Information
For background on the broader Perfect framework, see [perfect.org](http://perfect.org) and [PerfectlySoft/Perfect](https://github.com/PerfectlySoft/Perfect).

## Testing

The tests that need a server drop and recreate databases, so they are skipped (and reported as skipped) unless
`MARIA_TESTS=1` is set and `MARIA_TEST_PORT` names a port from 1 to 65535. There is no default port: the client would
otherwise fall back to 3306, which may be a real server. They connect to `127.0.0.1` as `root` with password `123` by
default; override with `MARIA_TEST_HOST`, `MARIA_TEST_USER` and `MARIA_TEST_PASSWORD`. `MARIA_TEST_HOST=localhost` is
refused, and so is an empty host, because the client then uses the Unix socket and ignores the port. The foreign-key
tests also need `MARIA_FK_LIVE_TESTS=1`, and their password defaults to empty rather than `123`. Two TLS tests need
more: one a non-loopback `MARIA_TEST_HOST`, the other a server without TLS named by `MARIA_TEST_NOTLS_PORT` (and
`MARIA_TEST_NOTLS_HOST`). For example, with the throwaway MariaDB container from `docker-compose.yml` on port 3308:

```sh
MARIA_TESTS=1 MARIA_TEST_PORT=3308 swift test
```
