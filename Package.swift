// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MariaDB",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "PerfectMariaDB", targets: ["MariaDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", branch: "main"),
    ],
    targets: [
        .systemLibrary(
            name: "mariadbclient",
            pkgConfig: "libmariadb",
            providers: [
                .apt(["libmariadb-dev"]),
                .brew(["mariadb-connector-c"]),
            ]
        ),
        .target(
            name: "MariaDB",
            dependencies: [
                "mariadbclient",
                .product(name: "PerfectCRUD", package: "Perfect-CRUD"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MariaDBTests",
            dependencies: ["MariaDB", "mariadbclient"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // macOS: search for dylibs before static archives in every -L directory, so
            // `-lmariadb` always finds the system libmariadb, never an archive in the build
            // products directory that matches case-insensitively. Test targets of dependencies
            // are never built, so this doesn't affect packages that depend on this one.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-search_dylibs_first"], .when(platforms: [.macOS]))]
        ),
    ]
)
