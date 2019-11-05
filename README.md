# Perfect - MariaDB Connector [简体中文](README.zh_CN.md)

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-5.0-orange.svg?style=flat" alt="Swift 5.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>



This project provides a Swift wrapper around the MariaDB client library, enabling access to MariaDB database servers.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not require PerfectLib or any other components.

Ensure you have installed and activated the latest Swift tool chain.


## OS X Build Notes

### To install MariaDB connector:

```bash
brew install mariadb-connector-c
```

## Linux Build Notes


Tests performed on Ubuntu 18.04. Prior to building this library, please ensure you install the required MariaDB library:

```bash
sudo apt-get install pkg-config libmariadb-dev  
```

On older distros (like 16.04), you may need to install libmariadb-client-lgpl-dev instead of libmariadb-dev. On older versions, you will also need to create a pkg-config file. In such cases, create /usr/lib/pkgconfig/libmariadb.pc and make it look something like this:

```
libdir=/usr/lib/x86_64-linux-gnu
includedir=/usr/include/mariadb

Name: libmariadb
Description: MariaDB Connector/C
Version: 5.5.0
Requires:
Cflags: -I${includedir}
Libs: -L${libdir} -lmariadb
Libs.private: -ldl -lm -lpthread
```

To test if pkg-config is working, try running the command:

```bash
pkg-config libmariadb --cflags --libs
```

## Building

Add this project as a dependency in your Package.swift file.

```
.package(url:"https://github.com/PerfectlySoft/Perfect-MariaDB.git", from: "4.0.0")
...
dependencies: ["MariaDB"]),
```


Import required libraries:
```
import MariaDB
import PerfectCRUD
```

Perfect-MariaDB supports the Perfect-CRUD protocol. Please check [Perfect-CRUD](https://github.com/PerfectlySoft/Perfect-CRUD.git) for more information.

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
