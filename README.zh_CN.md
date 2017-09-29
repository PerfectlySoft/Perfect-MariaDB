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
        <img src="https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat" alt="Swift 4.0">
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

请确保您已经安装并激活了最新版本的 Swift 4.0 tool chain 工具链。

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
.Package(url:"https://github.com/PerfectlySoft/Perfect-MariaDB.git", majorVersion: 2)
```

## 快速上手

首先增加库函数导入：
```
import MariaDB
```

设置数据库连接信息
```
let testHost = "127.0.0.1"
let testUser = "test"
// 请按照数据库服务器实际配置自行填写有关的信息
let testPassword = "password"
let testSchema = "schema"
```

创建MySQL实例（MariaDB是在MySQL基础上的新的品牌，所以函数内容还是MySQL）

```
	let dataMysql = MySQL()

    // need to make sure something is available.
    guard dataMysql.connect(host: testHost, user: testUser, password: testPassword ) else {
        // 出错了
        return
    }

    defer {
        dataMysql.close()  // 确保数据库在使用完毕后正常关闭
    }

    // 设置具体的数据库，假设数据库中有一个user表，尝试访问一下，如果无法访问就报错
    guard dataMysql.selectDatabase(named: testSchema) && dataMysql.query(statement: "select * from users limit 1") else {
        // 出错了

        return
    }

    // 将查询结果保存下来
    let results = dataMysql.storeResults()

    // 用一个数组来检查实际查询的信息
    var resultArray = [[String?]]()

    while let row = results?.next() {
        resultArray.append(row)

    }

	print(resultArray)

```


此外，更复杂的查询语句都可以按照您的意愿自行完成。

### 问题报告、内容贡献和客户支持

我们目前正在过渡到使用JIRA来处理所有源代码资源合并申请、修复漏洞以及其它有关问题。因此，GitHub 的“issues”问题报告功能已经被禁用了。

如果您发现了问题，或者希望为改进本文提供意见和建议，[请在这里指出](http://jira.perfect.org:8080/servicedesk/customer/portal/1).

在您开始之前，请参阅[目前待解决的问题清单](http://jira.perfect.org:8080/projects/ISS/issues).


## 更多信息
关于本项目更多内容，请参考[perfect.org](http://perfect.org).
