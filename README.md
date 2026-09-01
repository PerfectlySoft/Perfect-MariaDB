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

This package is consumed within the Perfect-Resurrection monorepo as a local sibling checkout, not a tagged GitHub release. Add it to your `Package.swift` as a relative path dependency, alongside Perfect-CRUD (required, since Perfect-MariaDB's CRUD support depends on it):

```swift
dependencies: [
    .package(path: "../Perfect-MariaDB"),
    .package(path: "../Perfect-CRUD"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            "MariaDB",
            .product(name: "PerfectCRUD", package: "Perfect-CRUD"),
        ]
    ),
]
```

This means Perfect-MariaDB must be checked out alongside its sibling Perfect-Resurrection repos (in particular `../Perfect-CRUD`) for the build to resolve.

Import required libraries:
```swift
import MariaDB
import PerfectCRUD
```

Perfect-MariaDB implements the Perfect-CRUD protocol via `MySQLDatabaseConfiguration` (see `Sources/MariaDB/MySQLCRUD.swift`), letting Perfect-CRUD's declarative model/query API target a MariaDB/MySQL server. See [Perfect-CRUD](../Perfect-CRUD) (a local sibling repo in this monorepo, not an external dependency) for the CRUD API itself.

Note: the source files retain their original `MySQLCRUD.swift`/`MySQLStmt.swift` naming from this package's shared lineage with [Perfect-MySQL](../Perfect-MySQL) — MariaDB is wire-compatible with the MySQL client protocol, and the two packages are separate, independently-buildable connectors in this ecosystem.

## Testing

A `MariaDBTests` target and a `docker-compose.yml` (spins up a local MariaDB container) are included for running the test suite against a real server.

## Further Information
For background on the broader Perfect framework, see [perfect.org](http://perfect.org) and [PerfectlySoft/Perfect](https://github.com/PerfectlySoft/Perfect).
