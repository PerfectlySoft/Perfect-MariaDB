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
    <a href="https://gitter.im/PerfectlySoft/Perfect?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge" target="_blank">
        <img src="https://img.shields.io/badge/Gitter-Join%20Chat-brightgreen.svg" alt="Join the chat at https://gitter.im/PerfectlySoft/Perfect">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>


该项目实现了一个对 MariaDB 数据库客户端的连接器函数封装，便于用于访问 MariaDB 服务器。

该软件使用SPM进行编译和测试，本软件也是[Perfect](https://github.com/PerfectlySoft/Perfect)项目的一部分。本软件包可独立使用，因此使用时可以脱离PerfectLib等其他组件。

请确保您已经安装并激活了最新版本的 Swift tool chain 工具链。

## OS X 编译时的注意事项

本软件组件需要[Home Brew](http://brew.sh)管理的 MariaDB 连接库函数二进制版本。
```bash
 brew install mariadb-connector-c
```

您必须手工处理pkg-config的.pc文件，比如/usr/local/lib/pkgconfig/mariadb.pc，内容类似如下：

```bash
libdir=/usr/local/lib/mariadb
includedir=/usr/local/include/mariadb

Name: mariadb
Description: MariaDB Connector/C
Version: 5.5.1
Requires:
Libs: -L${libdir} -lmariadb  -ldl -lm -lpthread
Cflags: -I${includedir}
Libs_r: -L${libdir} -lmariadb -ldl -lm -lpthread
```


为了pkg-config正常工作，最好编辑一下当前用户根目录的 ~/.bash_profile 文件，在最后一行增加以下内容：

```
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
```

编辑保存后，将pkg-config需要的变量导入当前环境：

```
source ~/.bash_profile
```

要验证是否配置成功，请使用命令：

```
$ pkg-config mariadb --cflags --libs
```

## Linux 编译时注意事项


该组件在 Ubuntu 16.04 测试通过。在编译本库函数之前，请确定安装了：

```
sudo apt-get install pkg-config libmariadb2 libmariadb-client-lgpl-dev  
```

与在MacOS下编译前的准备工作一致，Linux一样需要手工编辑pkg-config文件，比如 /usr/lib/pkgconfig/mariadb.pc 。请务必确保其内容正确无误，以下内容为该文件的一个模板：

```bash
libdir=/usr/lib/x86_64-linux-gnu
includedir=/usr/include/mariadb

Name: mariadb
Description: MariaDB Connector/C
Version: 5.5.0
Requires:
Libs: -L${libdir} -lmariadb  -ldl -lm -lpthread
Cflags: -I${includedir}
Libs_r: -L${libdir} -lmariadb -ldl -lm -lpthread
```

验证是否配置成功，请使用命令：

```
$ pkg-config mariadb --cflags --libs
```

## 编译

请在您的Package.swift文件下增加以下内容：

```
.package(url:"https://github.com/PerfectlySoft/Perfect-MariaDB.git", from: "4.0.0")
...
dependencies: ["MariaDB"]),
```

## 快速上手

首先增加库函数导入：
```
import MariaDB
```

Perfect-MariaDB 支持 Perfect-CRUD。详见[Perfect-CRUD操作手册](https://github.com/PerfectlySoft/Perfect-CRUD.git)

## 更多信息
关于本项目更多内容，请参考[perfect.org](http://perfect.org).
