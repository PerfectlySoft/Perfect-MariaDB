import mariadbclient
import Foundation

/// Converts between UTF-8 bytes and String. Invalid UTF-8 is replaced with U+FFFD rather than truncating.
struct UTF8Encoding {
    static func encode<S: Sequence>(bytes byts: S) -> String where S.Iterator.Element == UTF8.CodeUnit {
        return String(decoding: Array(byts), as: UTF8.self)
    }
    static func encode(_ ptr: UnsafePointer<UInt8>, count: Int) -> String {
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
    static func decode(string str: String) -> [UInt8] {
        return [UInt8](str.utf8)
    }
}

/// True for columns whose values are raw bytes: string and BLOB types in the binary character set
/// (BINARY, VARBINARY, BLOB, CAST(... AS BINARY), ...), plus BIT and GEOMETRY. Numeric and temporal
/// types also report the binary character set but aren't bytes.
func mysqlFieldIsBinary(_ field: UnsafeMutablePointer<MYSQL_FIELD>) -> Bool {
    switch field.pointee.type {
    case MYSQL_TYPE_BIT, MYSQL_TYPE_GEOMETRY:
        return true
    case MYSQL_TYPE_TINY_BLOB, MYSQL_TYPE_MEDIUM_BLOB, MYSQL_TYPE_LONG_BLOB, MYSQL_TYPE_BLOB,
         MYSQL_TYPE_STRING, MYSQL_TYPE_VAR_STRING, MYSQL_TYPE_VARCHAR:
        return field.pointee.charsetnr == 63 // binary
    default:
        return false
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
        MYSQL_OPT_SSL_MODE,
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
    /// Set when MYSQL_OPT_SSL_MODE asks for TLS, which libmariadb doesn't enforce itself.
    var sslModeRequiresTLS = false
    /// An error from connect() that libmariadb doesn't know about.
    var connectError: String?
    /// The options set so far, to set again on a fresh handle after connect() refuses a connection.
    var appliedOptions: [(MySQLOpt, OptionValue)] = []
    enum OptionValue {
        case none, bool(Bool), int(UInt32), string(String)
    }

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
        let code = mysql_errno(self.ptr!)
        if code == 0 && self.connectError != nil {
            return 2026 // CR_SSL_CONNECTION_ERROR
        }
        return code
    }

    public func errorMessage() -> String {
        if mysql_errno(self.ptr!) == 0, let connectError = self.connectError {
            return connectError
        }
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
        self.connectError = nil
        if self.sslModeRequiresTLS {
            // libmariadb's automatic reconnect would skip the check below.
            var off = my_bool(0)
            mysql_options(self.ptr!, MYSQL_OPT_RECONNECT, &off)
        }
        // CLIENT_REMEMBER_OPTIONS: libmariadb otherwise resets the options when a connection fails,
        // so a retry would quietly drop MYSQL_OPT_SSL_MODE (and everything else).
        let check = mysql_real_connect(self.ptr!, hostOrBlank.0!, userOrBlank.0!, passwordOrBlank.0!, dbOrBlank.0!, port, socketOrBlank.0!, flag | (1 << 31))
        guard check != nil && check == self.ptr else {
            return false
        }
        // libmariadb quietly falls back to plaintext when the server has no TLS. Refuse that
        // connection, and start a fresh handle with the same options so connect() can be retried.
        if self.sslModeRequiresTLS && mysql_get_ssl_cipher(self.ptr!) == nil {
            mysql_close(self.ptr!)
            self.ptr = mysql_init(nil)
            for (option, value) in self.appliedOptions {
                self.apply(option, value)
            }
            self.connectError = "SSL connection error: SSL is required, but the server does not support it"
            return false
        }
        return true
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
        // libmariadb has no such option; setOption(_:_: Int) maps it. Anywhere else, use a value
        // libmariadb rejects.
        case .MYSQL_OPT_SSL_MODE: return mysql_option(rawValue: 0x7FFF)
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
        return self.record(option, .none)
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt, _ b: Bool) -> Bool {
        return self.record(option, .bool(b))
    }

    /// MYSQL_OPT_SSL_MODE takes one of MySQL's SSL_MODE_* values (1 = DISABLED ... 5 = VERIFY_IDENTITY),
    /// mapped onto MYSQL_OPT_SSL_ENFORCE and MYSQL_OPT_SSL_VERIFY_SERVER_CERT:
    /// - REQUIRED: libmariadb doesn't refuse a server without TLS, so connect() does, but only after
    ///   authenticating in plaintext. Someone able to tamper with the connection can capture the
    ///   authentication exchange (or the password, if the server asks for mysql_clear_password).
    ///   Use VERIFY_IDENTITY, which fails before authenticating. REQUIRED also turns off
    ///   MYSQL_OPT_RECONNECT, since a reconnect could fall back to plaintext.
    /// - VERIFY_CA also checks the server's host name, except that Connector/C 3.4 checks neither the
    ///   host name nor (without MYSQL_OPT_SSL_CA) the CA on local connections.
    /// - DISABLED still uses TLS if MYSQL_OPT_SSL_CA, _CERT, _KEY, _CAPATH or _CIPHER is set.
    @discardableResult
    public func setOption(_ option: MySQLOpt, _ i: Int) -> Bool {
        guard let myI = UInt32(exactly: i) else {
            return false
        }
        return self.record(option, .int(myI))
    }

    @discardableResult
    public func setOption(_ option: MySQLOpt, _ s: String) -> Bool {
        return self.record(option, .string(s))
    }

    private func record(_ option: MySQLOpt, _ value: OptionValue) -> Bool {
        guard self.apply(option, value) else {
            return false
        }
        self.appliedOptions.append((option, value))
        return true
    }

    @discardableResult
    private func apply(_ option: MySQLOpt, _ value: OptionValue) -> Bool {
        let mysqlOption = exposedOptionToMySQLOption(option)
        switch value {
        case .none:
            return mysql_options(self.ptr!, mysqlOption, nil) == 0
        case .bool(let b):
            var myB = my_bool(b ? 1 : 0)
            return mysql_options(self.ptr!, mysqlOption, &myB) == 0
        case .int(var myI):
            if option == .MYSQL_OPT_SSL_MODE {
                guard perfect_mariadb_set_ssl_mode(self.ptr!, myI) == 0 else {
                    return false
                }
                self.sslModeRequiresTLS = myI >= SSL_MODE_REQUIRED.rawValue
                return true
            }
            return mysql_options(self.ptr!, mysqlOption, &myI) == 0
        case .string(let s):
            return s.withCString { mysql_options(self.ptr!, mysqlOption, $0) == 0 }
        }
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

        /// Invalid UTF-8 is replaced with U+FFFD. Use `nextBytes()` for binary columns
        /// (see `fieldIsBinary(at:)`).
        public func next() -> Element? {
            return nextRow { raw, len in
                raw.withMemoryRebound(to: UInt8.self, capacity: len) { UTF8Encoding.encode($0, count: len) }
            }
        }

        /// The next row as the exact bytes of each column (nil for NULL).
        /// Advances the same cursor as `next()`.
        public func nextBytes() -> [[UInt8]?]? {
            return nextRow { raw, len in
                raw.withMemoryRebound(to: UInt8.self, capacity: len) { Array(UnsafeBufferPointer(start: $0, count: len)) }
            }
        }

        private func nextRow<T>(_ convert: (UnsafeMutablePointer<CChar>, Int) -> T) -> [T?]? {
            guard let row = mysql_fetch_row(self.ptr), let lengths = mysql_fetch_lengths(self.ptr) else {
                return nil
            }
            var ret = [T?]()
            for fieldIdx in 0..<self.numFields() {
                if let raw = row[fieldIdx] {
                    ret.append(convert(raw, Int(lengths[fieldIdx])))
                } else {
                    ret.append(nil)
                }
            }
            return ret
        }

        /// True if the column's values are raw bytes: BINARY, VARBINARY, BLOB and other string types in
        /// the binary character set, plus BIT and GEOMETRY. These are the columns `MySQLStmt` returns as
        /// `[UInt8]`; read them here with `nextBytes()`, since `next()` can't represent them as text.
        /// False after `close()`.
        public func fieldIsBinary(at index: Int) -> Bool {
            guard let ptr = self.ptr, index >= 0, index < Int(mysql_num_fields(ptr)),
                  let field = mysql_fetch_field_direct(ptr, UInt32(index)) else {
                return false
            }
            return mysqlFieldIsBinary(field)
        }

        public func forEachRow(callback: (Element) -> ()) {
            while let element = self.next() {
                callback(element)
            }
        }

        /// Passes each remaining row's exact column bytes to the callback provided.
        public func forEachRowBytes(callback: ([[UInt8]?]) -> ()) {
            while let element = self.nextBytes() {
                callback(element)
            }
        }
    }
}
