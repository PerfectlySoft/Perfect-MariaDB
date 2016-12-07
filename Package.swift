//
//  Package.swift
//  Perfect-MariaDB
//
//  Created by Rockford Wei on 10/04/16.
//	Copyright (C) 2016 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PackageDescription

#if os(OSX)
let package = Package(
    name: "MariaDB",
    targets: [],
    dependencies: [
                      .Package(url: "https://github.com/PerfectlySoft/Perfect-mariadbclient.git", majorVersion: 2, minor: 0)
    ],
    exclude: []
)
#else
let package = Package(
    name: "MariaDB",
    targets: [],
    dependencies: [
                      .Package(url: "https://github.com/PerfectlySoft/Perfect-mariadbclient-Linux.git", majorVersion: 2, minor: 0)
    ],
    exclude: []
)
#endif
