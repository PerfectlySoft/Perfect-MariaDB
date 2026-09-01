import mariadbclient
import Foundation

struct GenerateFromPointer<T>: IteratorProtocol {
    typealias Element = T
    var count = 0
    var pos = 0
    var from: UnsafeMutablePointer<T>
    init(from: UnsafeMutablePointer<T>, count: Int) {
        self.from = from
        self.count = count
    }
    mutating func next() -> Element? {
        guard count > 0 else { return nil }
        self.count -= 1
        let result = self.from[self.pos]
        self.pos += 1
        return result
    }
}

struct Encoding {
    static func encode<D: UnicodeCodec, G: IteratorProtocol>(codec inCodec: D, generator: G) -> String where G.Element == D.CodeUnit {
        var encodedString = ""
        var finished = false
        var mutableDecoder = inCodec
        var mutableGenerator = generator
        repeat {
            let decodingResult = mutableDecoder.decode(&mutableGenerator)
            switch decodingResult {
            case .scalarValue(let char): encodedString.append(String(char))
            case .emptyInput: finished = true
            case .error: finished = true
            }
        } while !finished
        return encodedString
    }
}

struct UTF8Encoding {
    static func encode<G: IteratorProtocol>(generator gen: G) -> String where G.Element == UTF8.CodeUnit {
        return Encoding.encode(codec: UTF8(), generator: gen)
    }
    static func encode<S: Sequence>(bytes byts: S) -> String where S.Iterator.Element == UTF8.CodeUnit {
        return encode(generator: byts.makeIterator())
    }
    static func decode(string str: String) -> [UInt8] {
        return [UInt8](str.utf8)
    }
}

public enum MySQLOpt {
    case MYSQL_OPT_CONNECT_TIMEOUT, MYSQL_OPT_COMPRESS, MYSQL_OPT_NAMED_PIPE,
        MYSQL_INIT_COMMAND, MYSQL_READ_DEFAULT_FILE, MYSQL_READ_DEFAULT_GROUP,
        MYSQL_SET_CHARSET_DIR, MYSQL_SET_CHARSET_NAME, MYSQL_OPT_LOCAL_INFILE,
        MYSQL_OPT_PROTOCOL, MYSQL_SHARED_MEMORY_BASE_NAME, MYSQL_OPT_READ_TIMEOUT,
        MYSQL_OPT_WRITE_TIMEOUT, MYSQL_OPT_USE_RESULT,
        MYSQL_OPT_USE_REMOTE_CONNECTION, MYSQL_OPT_USE_EMBEDDED_CONNECTION,
        MYSQL_OPT_GUESS_CONNECTION, MYSQL_SET_CLIENT_IP, MYSQL_SECURE_AUTH,
        MYSQL_REPORT_DATA_TRUNCATION, MYSQL_OPT_RECONNECT,
        MYSQL_OPT_SSL_VERIFY_SERVER_CERT, MYSQL_PLUGIN_DIR, MYSQL_DEFAULT_AUTH,
        MYSQL_OPT_BIND,
        MYSQL_OPT_SSL_KEY, MYSQL_OPT_SSL_CERT,
        MYSQL_OPT_SSL_CA, MYSQL_OPT_SSL_CAPATH, MYSQL_OPT_SSL_CIPHER,
        MYSQL_OPT_SSL_CRL, MYSQL_OPT_SSL_CRLPATH,
        MYSQL_OPT_CONNECT_ATTR_RESET, MYSQL_OPT_CONNECT_ATTR_ADD,
        MYSQL_OPT_CONNECT_ATTR_DELETE,
        MYSQL_SERVER_PUBLIC_KEY,
        MYSQL_ENABLE_CLEARTEXT_PLUGIN
}

public final class MySQL: @unchecked Sendable {

    var ptr: UnsafeMutablePointer<MYSQL>?

    public static func clientInfo() -> String {
        return String(validatingCString: mysql_get_client_info()) ?? ""
    }

    nonisolated(unsafe) private static var initOnce: Bool = {
        mysql_server_init(0, nil, nil)
        return true
    }()

    public init() {
        _ = MySQL.initOnce
        self.ptr = mysql_init(nil)
    }

    deinit {
        self.close()
    }

    public func ping() -> Bool {
        guard let ref = ptr else { return false }
        return 0 == mysql_ping(ref)
    }

    public func close() {
        if self.ptr != nil {
            mysql_close(self.ptr!)
            self.ptr = nil
        }
    }

    public func errorCode() -> UInt32 {
        return mysql_errno(self.ptr!)
    }

    public func errorMessage() -> String {
        return String(validatingCString: mysql_error(self.ptr!)) ?? ""
    }

    public func serverVersion() -> Int {
        return Int(mysql_get_server_version(self.ptr!))
    }

    static func convertString(_ s: String?) -> (UnsafeMutablePointer<Int8>?, Int) {
        var ret: (UnsafeMutablePointer<Int8>?, Int) = (UnsafeMutablePointer<Int8>(nil as OpaquePointer?), 0)
        guard let notNilString = s else {
            return convertString("")
        }
        notNilString.withCString { p in
            var c = 0
            while p[c] != 0 { c += 1 }
            c += 1
            let alloced = UnsafeMutablePointer<Int8>.allocate(capacity: c)
            alloced.initialize(to: 0)
            for i in 0..<c { alloced[i] = p[i] }
            alloced[c-1] = 0
            ret = (alloced, c)
        }
        return ret
    }

    func cleanConvertedString(_ pair: (UnsafeMutablePointer<Int8>?, Int)) {
        if let p0 = pair.0, pair.1 > 0 {
            p0.deinitialize(count: pair.1)
            p0.deallocate()
        }
    }

    public func connect(host hst: String? = nil, user: String? = nil, password: String? = nil, db: String? = nil, port: UInt32 = 0, socket: String? = nil, flag: UInt = 0) -> Bool {
        if self.ptr == nil { self.ptr = mysql_init(nil) }
        let hostOrBlank = MySQL.convertString(hst)
        let userOrBlank = MySQL.convertString(user)
        let passwordOrBlank = MySQL.convertString(password)
        let dbOrBlank = MySQL.convertString(db)
        let socketOrBlank = MySQL.convertString(socket)
        defer {
            self.cleanConvertedString(hostOrBlank)
            self.cleanConvertedString(userOrBlank)
            self.cleanConvertedString(passwordOrBlank)
            self.cleanConvertedString(dbOrBlank)
            self.cleanConvertedString(socketOrBlank)
        }
        let check = mysql_real_connect(self.ptr!, hostOrBlank.0!, userOrBlank.0!, passwordOrBlank.0!, dbOrBlank.0!, port, socketOrBlank.0!, flag)
        return check != nil && check == self.ptr
    }

    public func selectDatabase(named namd: String) -> Bool {
        return mysql_select_db(self.ptr!, namd) == 0
    }

    public func listTables(wildcard wild: String? = nil) -> [String] {
        var result = [String]()
        let res = wild == nil ? mysql_list_tables(self.ptr!, nil) : mysql_list_tables(self.ptr!, wild!)
        if res != nil {
            var row = mysql_fetch_row(res)
            while row != nil {
                if let tabPtr = row![0] {
                    result.append(String(cString: tabPtr))
                }
                row = mysql_fetch_row(res)
            }
            mysql_free_result(res)
        }
        return result
    }

    public func listDatabases(wildcard wild: String? = nil) -> [String] {
        var result = [String]()
        let res = wild == nil ? mysql_list_dbs(self.ptr!, nil) : mysql_list_dbs(self.ptr!, wild!)
        if res != nil {
            var row = mysql_fetch_row(res)
            while row != nil {
                if let tabPtr = row![0] {
                    result.append(String(cString: tabPtr))
                }
                row = mysql_fetch_row(res)
            }
            mysql_free_result(res)
        }
        return result
    }

    public func commit() -> Bool {
        return mysql_commit(self.ptr!) == 1
    }

    public func rollback() -> Bool {
        return mysql_rollback(self.ptr!) == 1
    }

    public func moreResults() -> Bool {
        return mysql_more_results(self.ptr!) == 1
    }

    public func nextResult() -> Int {
        return Int(mysql_next_result(self.ptr!))
    }

    public func query(statement stmt: String, multiple: Bool = false) -> Bool {
        if multiple {
            return mysql_query(self.ptr!, stmt) == 0
        } else {
            return mysql_real_query(self.ptr!, stmt, UInt(stmt.utf8.count)) == 0
        }
    }

    public func storeResults() -> MySQL.Results? {
        guard let ret = mysql_store_result(self.ptr) else { return nil }
        return MySQL.Results(ret)
    }

    func exposedOptionToMySQLOption(_ o: MySQLOpt) -> mysql_option {
        switch o {
        case .MYSQL_OPT_CONNECT_TIMEOUT: return MYSQL_OPT_CONNECT_TIMEOUT
        case .MYSQL_OPT_COMPRESS: return MYSQL_OPT_COMPRESS
        case .MYSQL_OPT_NAMED_PIPE: return MYSQL_OPT_NAMED_PIPE
        case .MYSQL_INIT_COMMAND: return MYSQL_INIT_COMMAND
        case .MYSQL_READ_DEFAULT_FILE: return MYSQL_READ_DEFAULT_FILE
        case .MYSQL_READ_DEFAULT_GROUP: return MYSQL_READ_DEFAULT_GROUP
        case .MYSQL_SET_CHARSET_DIR: return MYSQL_SET_CHARSET_DIR
        case .MYSQL_SET_CHARSET_NAME: return MYSQL_SET_CHARSET_NAME
        case .MYSQL_OPT_LOCAL_INFILE: return MYSQL_OPT_LOCAL_INFILE
        case .MYSQL_OPT_PROTOCOL: return MYSQL_OPT_PROTOCOL
        case .MYSQL_SHARED_MEMORY_BASE_NAME: return MYSQL_SHARED_MEMORY_BASE_NAME
        case .MYSQL_OPT_READ_TIMEOUT: return MYSQL_OPT_READ_TIMEOUT
        case .MYSQL_OPT_WRITE_TIMEOUT: return MYSQL_OPT_WRITE_TIMEOUT
        case .MYSQL_OPT_USE_RESULT: return MYSQL_OPT_USE_RESULT
        case .MYSQL_OPT_USE_REMOTE_CONNECTION: return MYSQL_OPT_USE_REMOTE_CONNECTION
        case .MYSQL_OPT_USE_EMBEDDED_CONNECTION: return MYSQL_OPT_USE_EMBEDDED_CONNECTION
        case .MYSQL_OPT_GUESS_CONNECTION: return MYSQL_OPT_GUESS_CONNECTION
        case .MYSQL_SET_CLIENT_IP: return MYSQL_SET_CLIENT_IP
        case .MYSQL_SECURE_AUTH: return MYSQL_SECURE_AUTH
        case .MYSQL_REPORT_DATA_TRUNCATION: return MYSQL_REPORT_DATA_TRUNCATION
        case .MYSQL_OPT_RECONNECT: return MYSQL_OPT_RECONNECT
        case .MYSQL_OPT_SSL_VERIFY_SERVER_CERT: return MYSQL_OPT_SSL_VERIFY_SERVER_CERT
        case .MYSQL_PLUGIN_DIR: return MYSQL_PLUGIN_DIR
        case .MYSQL_DEFAULT_AUTH: return MYSQL_DEFAULT_AUTH
        case .MYSQL_OPT_BIND: return MYSQL_OPT_BIND
        case .MYSQL_OPT_SSL_KEY: return MYSQL_OPT_SSL_KEY
        case .MYSQL_OPT_SSL_CERT: return MYSQL_OPT_SSL_CERT
        case .MYSQL_OPT_SSL_CA: return MYSQL_OPT_SSL_CA
        case .MYSQL_OPT_SSL_CAPATH: return MYSQL_OPT_SSL_CAPATH
        case .MYSQL_OPT_SSL_CIPHER: return MYSQL_OPT_SSL_CIPHER
        case .MYSQL_OPT_SSL_CRL: return MYSQL_OPT_SSL_CRL
        case .MYSQL_OPT_SSL_CRLPATH: return MYSQL_OPT_SSL_CRLPATH
        case .MYSQL_OPT_CONNECT_ATTR_RESET: return MYSQL_OPT_CONNECT_ATTR_RESET
        case .MYSQL_OPT_CONNECT_ATTR_ADD: return MYSQL_OPT_CONNECT_ATTR_ADD
        case .MYSQL_OPT_CONNECT_ATTR_DELETE: return MYSQL_OPT_CONNECT_ATTR_DELETE
        case .MYSQL_SERVER_PUBLIC_KEY: return MYSQL_SERVER_PUBLIC_KEY
        case .MYSQL_ENABLE_CLEARTEXT_PLUGIN: return MYSQL_ENABLE_CLEARTEXT_PLUGIN
        }
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt) -> Bool {
        return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), nil) == 0
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt, _ b: Bool) -> Bool {
        var myB = my_bool(b ? 1 : 0)
        return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), &myB) == 0
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt, _ i: Int) -> Bool {
        var myI = UInt32(i)
        return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), &myI) == 0
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt, _ s: String) -> Bool {
        var b = false
        s.withCString { p in
            b = mysql_options(self.ptr!, exposedOptionToMySQLOption(option), p) == 0
        }
        return b
    }

    public final class Results: IteratorProtocol, @unchecked Sendable {
        var ptr: UnsafeMutablePointer<MYSQL_RES>?
        public typealias Element = [String?]

        init(_ ptr: UnsafeMutablePointer<MYSQL_RES>) {
            self.ptr = ptr
        }

        deinit { self.close() }

        public func close() {
            if self.ptr != nil {
                mysql_free_result(self.ptr!)
                self.ptr = nil
            }
        }

        public func dataSeek(_ offset: UInt) {
            mysql_data_seek(self.ptr!, my_ulonglong(offset))
        }

        public func numRows() -> Int {
            return Int(mysql_num_rows(self.ptr!))
        }

        public func numFields() -> Int {
            return Int(mysql_num_fields(self.ptr!))
        }

        public func next() -> Element? {
            guard let row = mysql_fetch_row(self.ptr), let lengths = mysql_fetch_lengths(self.ptr) else {
                return nil
            }
            var ret = [String?]()
            for fieldIdx in 0..<self.numFields() {
                let length = lengths[fieldIdx]
                let rowVal = row[fieldIdx]
                let len = Int(length)
                if let raw = rowVal {
                    let s = raw.withMemoryRebound(to: UInt8.self, capacity: len) {
                        UTF8Encoding.encode(generator: GenerateFromPointer(from: $0, count: len))
                    }
                    ret.append(s)
                } else {
                    ret.append(nil)
                }
            }
            return ret
        }

        public func forEachRow(callback: (Element) -> ()) {
            while let element = self.next() {
                callback(element)
            }
        }
    }
}
