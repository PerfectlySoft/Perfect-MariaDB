# Perfect - MariaDB 连接器

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="https://gitter.im/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_2_Git.jpg" alt="Chat on Gitter" />
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
        <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="https://gitter.im/PerfectlySoft/Perfect?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge" target="_blank">
        <img src="https://img.shields.io/badge/Gitter-Join%20Chat-brightgreen.svg" alt="Join the chat at https://gitter.im/PerfectlySoft/Perfect">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>


该项目实现了一个对 MariaDB 数据库客户端的连接器函数封装，便于用于访问 MariaDB 服务器。

该软件使用SPM进行编译和测试，本软件也是[Perfect](https://github.com/PerfectlySoft/Perfect)项目的一部分。本软件包可独立使用，因此使用时可以脱离PerfectLib等其他组件。

需要 Swift 6.2 或更高版本，支持 macOS 12+ 和 Linux。最新的编译说明、TLS 说明以及从 3.x 迁移的说明请参阅[英文 README](README.md)。

## macOS 编译时的注意事项

```bash
brew install mariadb-connector-c
```

Homebrew 以 keg-only 方式安装该库。Swift 6.4 可以直接找到它；使用更早的工具链时（例如 Xcode 26.3 中的 Swift 6.2），请先设置：

```bash
export PKG_CONFIG_PATH="$(brew --prefix mariadb-connector-c)/lib/pkgconfig"
```

## Linux 编译时注意事项

```bash
sudo apt-get install pkg-config libmariadb-dev
```

验证是否配置成功，请使用命令：

```
$ pkg-config libmariadb --cflags --libs
```

## 编译

请在您的 Package.swift 文件中增加以下内容：

```swift
.package(url: "https://github.com/PerfectlySoft/Perfect-MariaDB.git", from: "4.0.0"),
.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "3.0.1"),
...
dependencies: [
    .product(name: "PerfectMariaDB", package: "Perfect-MariaDB"),
    .product(name: "PerfectCRUD", package: "Perfect-CRUD"),
]),
```

库产品名为 `PerfectMariaDB`（与 `PerfectMySQL`、`PerfectPostgreSQL` 一致），模块仍以 `import MariaDB` 导入。**破坏性变更：** 在 3.x 中该产品名为 `MariaDB`，请把 `.product(name: "MariaDB", ...)`（或直接写的 `"MariaDB"`）改为 `.product(name: "PerfectMariaDB", package: "Perfect-MariaDB")`。

## 快速上手

首先增加库函数导入：
```
import MariaDB
```

Perfect-MariaDB 支持 Perfect-CRUD。详见[Perfect-CRUD操作手册](https://github.com/PerfectlySoft/Perfect-CRUD.git)

## 更多信息
关于本项目更多内容，请参考[perfect.org](http://perfect.org).
