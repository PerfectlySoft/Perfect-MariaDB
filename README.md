# Perfect - MariaDB Connector

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B-lightgray.svg?style=flat" alt="Platforms macOS 12+">
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

## macOS Build Notes

`Package.swift` declares `platforms: [.macOS(.v12)]`.

### To install the MariaDB connector:

```bash
brew install mariadb-connector-c
```

## Linux Build Notes

Linux is not declared in the `platforms` array in `Package.swift` (only `.macOS(.v12)` is), so it is not an officially asserted/tested target. That said, the `mariadbclient` system-library target still declares an `.apt(["libmariadb-dev"])` provider, so a Linux build remains possible at the toolchain level if you ensure the library is installed:

```bash
sudo apt-get install pkg-config libmariadb-dev
```

To test if pkg-config is working, try running the command:

```bash
pkg-config libmariadb --cflags --libs
```

## Building

Add it to your `Package.swift`. There is no tagged release of the Swift 6 version yet, so depend on `main`:

```swift
dependencies: [
    .package(url: "https://github.com/PerfectlySoft/Perfect-MariaDB.git", branch: "main"),
    .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", branch: "main"),
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
imported as `MariaDB`. **Breaking change:** it used to be called `MariaDB`, so if you depended on `main` before this
rename, change `.product(name: "MariaDB", ...)` (or a bare `"MariaDB"` dependency) to
`.product(name: "PerfectMariaDB", package: "Perfect-MariaDB")`.

Import required libraries:
```swift
import MariaDB
import PerfectCRUD
```

Perfect-MariaDB implements the Perfect-CRUD protocol via `MySQLDatabaseConfiguration` (see `Sources/MariaDB/MySQLCRUD.swift`), letting Perfect-CRUD's declarative model/query API target a MariaDB/MySQL server. See [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD) for the CRUD API itself.

Note: the source files retain their original `MySQLCRUD.swift`/`MySQLStmt.swift` naming from this package's shared lineage with [Perfect-MySQL](https://github.com/PerfectlySoft/Perfect-MySQL) — MariaDB is wire-compatible with the MySQL client protocol, and the two packages are separate, independently-buildable connectors in this ecosystem.

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

## Testing

A `MariaDBTests` target and a `docker-compose.yml` (spins up a local MariaDB container) are included for running the test suite against a real server.

## Further Information
For background on the broader Perfect framework, see [perfect.org](http://perfect.org) and [PerfectlySoft/Perfect](https://github.com/PerfectlySoft/Perfect).

## Testing

The tests that need a server are skipped unless `MARIA_TESTS=1` is set. They connect to `127.0.0.1` as `root` with
password `123` by default; override with `MARIA_TEST_HOST`, `MARIA_TEST_PORT`, `MARIA_TEST_USER` and
`MARIA_TEST_PASSWORD`. For example, with a throwaway MariaDB container on port 3308:

```sh
MARIA_TESTS=1 MARIA_TEST_PORT=3308 swift test
```
