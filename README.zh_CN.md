# Perfect - MariaDB Connector [English](README.md)

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
        <img src="https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat" alt="Swift 3.0">
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

请确保您已经安装并激活了最新版本的 Swift 3.0 tool chain 工具链。

### 问题报告、内容贡献和客户支持

我们目前正在过渡到使用JIRA来处理所有源代码资源合并申请、修复漏洞以及其它有关问题。因此，GitHub 的“issues”问题报告功能已经被禁用了。

如果您发现了问题，或者希望为改进本文提供意见和建议，[请在这里指出](http://jira.perfect.org:8080/servicedesk/customer/portal/1).

在您开始之前，请参阅[目前待解决的问题清单](http://jira.perfect.org:8080/projects/ISS/issues).

## OS X 编译时的注意事项

本软件组件需要[Home Brew](http://brew.sh)管理的 MariaDB 二进制版本。

在 macOS X 下安装 Home Brew 的方法：

```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

完成后可以安装 MariaDB：

```
brew install mariadb
```

编译时比较稳妥的方法时用Xcode进行整体编译。在完成git 下载后，可以使用SPM命令生成Xcode工程：

```
swift package generate-xcodeproj
```

如果不用Xcode，那么您必须手工处理pkg-config的.pc文件，比如/usr/local/lib/pkgconfig/mariadb.pc，内容类似如下：

```
Name: mariadb
Description: MariaDB Connector/C
Version: 5.5.1
Requires:
Libs: -L/usr/local/Cellar/mariadb-connector-c/2.2.2/lib/mariadb -lmariadb  -ldl -lm -lpthread
Cflags: -I/usr/local/Cellar/mariadb-connector-c/2.2.2/include/mariadb -I/usr/local/Cellar/mariadb-connector-c/2.2.2/include/mariadb/mysqlLibs_r: -L/usr/local/Cellar/mariadb-connector-c/2.2.2/lib/mariadb -lmariadb -ldl -lm -lpthread
Plugindir: /usr/local/Cellar/mariadb-connector-c/2.2.2/mariadb/lib/plugin
Include: -I/usr/local/Cellar/mariadb-connector-c/2.2.2/include/mariadb -I/usr/local/Cellar/mariadb-connector-c/2.2.2/include/mariadb/mysql
```

请 **手工** 处理好上述文件中的各个路径。如果不知道具体的编译选项，可以尝试使用终端命令行：mariadb_config 检查mariadb的客户端配置：

```
mariadb_config
```

为了pkg-config正常工作，最好编辑一下当前用户根目录的 ~/.bash_profile 文件，在最后一行增加以下内容：

```
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/pkgconfig"
```

编辑保存后，将pkg-config需要的变量导入当前环境：

```
source ~/.bash_profile
```

上述操作的目的时正确配置clang + pkg-config。关于pkg-config命令的更多信息，请参考终端命令行下的手册：

```
man pkg-config
```

## Linux 编译时注意事项


该组件在 Ubuntu 16.04 测试通过。在编译本库函数之前，请确定安装了：

```
sudo apt-get install clang
sudo apt-get install pkg-config
sudo apt-get install libmariadb2
sudo apt-get install libmariadb-client-lgpl-dev
```

与在MacOS下编译前的准备工作一致，Linux一样需要手工编辑pkg-config文件，比如 /usr/lib/pkgconfig/mariadb.pc 。请务必确保其内容正确无误，以下内容为该文件的一个模板：

```
libdir=/usr/lib/x86_64-linux-gnu
includedir=/usr/include/mariadb

Name: mariadb
Description: MariaDB Connector/C
Version: 5.5.0
Requires:
Libs: -L/usr/lib/x86_64-linux-gnu -lmariadb
Cflags: -I/usr/include/mariadb -g -O2 -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2  -Wunused -Wno-uninitialize
```

## 编译

请在您的Package.swift文件下增加以下内容：

```
.Package(url:"https://github.com/PerfectlySoft/Perfect-MariaDB.git", majorVersion: 2, minor: 0)
```

## 快速上手

以下命令快速下载克隆一个空白的项目模板：
```
git clone https://github.com/PerfectlySoft/PerfectTemplate.git
cd PerfectTemplate
```
增加文件依存关系：
```
let package = Package(
 name: "PerfectTemplate",
 targets: [],
 dependencies: [
     .Package(url:"https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 2, minor: 0),
     .Package(url:"https://github.com/PerfectlySoft/Perfect-MariaDB.git", majorVersion: 2, minor: 0)
    ]
)
```
创建Xcode工程文件：
```
swift package generate-xcodeproj
```
在Xcode中打开PerfectTemplate.xcodeproj工程。

项目随后可以编译，并可以直接在本地8181端口运行一个独立的Web服务器。

特别注意：当在工程中增加一个新的依存关系时，SPM必须 ***重新*** 生成一个新的Xcode工程。注意之前您对这个工程文件.xcodeproj做过的任何手工改动都会被覆盖。

## 连接到MariaDB，并从数据表中选择数据进行查询

您的源代码Sources 目录下main.swift文件可以参考如下内容

首先导入所需函数库

```
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
```

为HTTP服务器创建一个实例并且增加路由：
```
// 创建HTTP服务器。
let server = HTTPServer()

// 注册路由和路由处理函数
var routes = Routes()
routes.add(method: .get, uri: "/", handler: {
		request, response in
		response.appendBody(string: "<html><title>Hello, world!</title><body>Hello, world!</body></html>")
		response.completed()
	}
)

//下面这个路由是用于取得数据的
routes.add(method: .get, uri: "/use", handler: useMysql)

// 将路由注册到服务器上
server.addRoutes(routes)
```

验证服务器设置：
```
// 监听8181端口
server.serverPort = 8181

// 设置文档根目录。这一步是可选的，如果有静态页面等内容才需要追加。
// 设置文档根目录会把所有默认路由 /** 都定向到静态页面上去。
server.documentRoot = "./webroot"
```

收集命令行参数并且配置服务器。服务器详细参数配置请在命令行加入 --help 进行参考。
```
configureServer(server)
```
启动服务器。请注意任何在server.start()之后的所有程序行都是实际上无法执行的。
```
do {
	// 启动HTTP 服务器
	try server.start()

} catch PerfectError.networkError(let err, let msg) {
	print("网路异常： \(err) \(msg)")
}
```

在您的项目中增加一个文件，确定位于Sources源程序目录下，比如mariadb__quickstart.swift。

首先增加库函数导入：
```
import PerfectLib
import MariaDB
import PerfectHTTP
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
```

下列函数将接待HTTP路由请求并设置为一个MySQL连接：

```
public func useMysql(_ request: HTTPRequest, response: HTTPResponse) {

    // need to make sure something is available.
    guard dataMysql.connect(host: testHost, user: testUser, password: testPassword ) else {
        Log.info(message: "无法连接到数据库 \(testHost)")
        return
    }

    defer {
        dataMysql.close()  // 确保数据库在使用完毕后正常关闭
    }

    // 设置具体的数据库，假设数据库中有一个user表，尝试访问一下，如果无法访问就报错
    guard dataMysql.selectDatabase(named: testSchema) && dataMysql.query(statement: "select * from users limit 1") else {
        Log.info(message: "数据库选择失败： \(dataMysql.errorCode()) \(dataMysql.errorMessage())")

        return
    }

    // 将查询结果保存下来
    let results = dataMysql.storeResults()

    // 用一个数组来检查实际查询的信息
    var resultArray = [[String?]]()

    while let row = results?.next() {
        resultArray.append(row)

    }

   // 将查询结果返回给HTTP的请求
   response.appendBody(string: "<html><title>Mysql Test</title><body>\(resultArray.debugDescription)</body></html>")
    response.completed()

}
```

此外，更复杂的查询语句都可以按照您的意愿自行完成。



## 更多信息
关于本项目更多内容，请参考[perfect.org](http://perfect.org).
