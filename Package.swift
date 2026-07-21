// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MariaDB",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MariaDB", targets: ["MariaDB"]),
    ],
    dependencies: [
        .package(url: "https://github.com/taplin/Perfect-CRUD.git", branch: "main"),
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
