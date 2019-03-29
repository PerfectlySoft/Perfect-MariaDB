//
//  MariaDB.swift
//  MariaDB
//
//  Created as MySQL.swift by Kyle Jessup on 2015-10-01.
//  Modified by Rockford Wei on 2016-10-04
//	Copyright (C) 2015 PerfectlySoft, Inc.
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

#if os(Linux)
	import Glibc
#endif
import mariadbclient
import Foundation
/// This class permits an UnsafeMutablePointer to be used as a IteratorProtocol
struct GenerateFromPointer<T> : IteratorProtocol {

	typealias Element = T

	var count = 0
	var pos = 0
	var from: UnsafeMutablePointer<T>

	/// Initialize given an UnsafeMutablePointer and the number of elements pointed to.
	init(from: UnsafeMutablePointer<T>, count: Int) {
		self.from = from
		self.count = count
	}

	/// Return the next element or nil if the sequence has been exhausted.
	mutating func next() -> Element? {
		guard count > 0 else {
			return nil
		}
		self.count -= 1
		let result = self.from[self.pos]
		self.pos += 1
		return result
	}
}

/// A generalized wrapper around the Unicode codec operations.
struct Encoding {
	/// Return a String given a character generator.
	static func encode<D : UnicodeCodec, G : IteratorProtocol>(codec inCodec: D, generator: G) -> String where G.Element == D.CodeUnit {
		var encodedString = ""
		var finished: Bool = false
		var mutableDecoder = inCodec
		var mutableGenerator = generator
		repeat {
			let decodingResult = mutableDecoder.decode(&mutableGenerator)
			switch decodingResult {
			case .scalarValue(let char):
				encodedString.append(String(char))
			case .emptyInput:
				finished = true
				/* ignore errors and unexpected values */
			case .error:
				finished = true
			}
		} while !finished
		return encodedString
	}
}

/// Utility wrapper permitting a UTF-8 character generator to encode a String. Also permits a String to be converted into a UTF-8 byte array.
struct UTF8Encoding {
	/// Use a character generator to create a String.
	static func encode<G : IteratorProtocol>(generator gen: G) -> String where G.Element == UTF8.CodeUnit {
		return Encoding.encode(codec: UTF8(), generator: gen)
	}

	/// Use a character sequence to create a String.
	static func encode<S : Sequence>(bytes byts: S) -> String where S.Iterator.Element == UTF8.CodeUnit {
		return encode(generator: byts.makeIterator())
	}

	/// Decode a String into an array of UInt8.
	static func decode(string str: String) -> Array<UInt8> {
		return [UInt8](str.utf8)
	}
}

#if os(Linux)
/// enum for mysql options
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
		MYSQL_OPT_CONNECT_ATTR_DELETE
///		MYSQL_SERVER_PUBLIC_KEY,
///		MYSQL_ENABLE_CLEARTEXT_PLUGIN
///		MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
}
#else
/// enum for mysql options
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
///	This feature is not available in MariaDB
///		MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
}
#endif


/// Provide access to MySQL connector functions
public final class MySQL {

	static private var dispatchOnce = pthread_once_t()

	var ptr: UnsafeMutablePointer<MYSQL>?

    /// Returns client info from mysql_get_client_info
	public static func clientInfo() -> String {
		return String(validatingUTF8: mysql_get_client_info()) ?? ""
	}

    private static var initOnce: Bool = {
        mysql_server_init(0, nil, nil)
        return true
    }()

    /// Create mysql server connection and set ptr
    public init() {
        _ = MySQL.initOnce
        self.ptr = mysql_init(nil)
    }

	deinit {
		self.close()
	}

  /// ping the server to check the connectivity and reconnect if possible
  /// - returns: true for connection OK
  public func ping() -> Bool {
    if let ref = ptr, 0 == mysql_ping(ref) {
      return true
    } else {
      return false
    }
  }
    /// Close connection and set ptr to nil
	public func close() {
		if self.ptr != nil {
			mysql_close(self.ptr!)
			self.ptr = nil
		}
	}
	/// Return mysql error number
	public func errorCode() -> UInt32 {
		return mysql_errno(self.ptr!)
	}
	/// Return mysql error message
	public func errorMessage() -> String {
		return String(validatingUTF8: mysql_error(self.ptr!)) ?? ""
	}

    /// Return mysql server version
	public func serverVersion() -> Int {
		return Int(mysql_get_server_version(self.ptr!))
	}

	/// returns an allocated buffer holding the string's contents and the full size in bytes which was allocated
	/// An empty (but not nil) string would have a count of 1
	static func convertString(_ s: String?) -> (UnsafeMutablePointer<Int8>?, Int) {
        // this can be cleaned up with Swift 2.2 support is no longer required
		var ret: (UnsafeMutablePointer<Int8>?, Int) = (UnsafeMutablePointer<Int8>(nil as OpaquePointer?), 0)
		guard let notNilString = s else {
			return convertString("")
		}
		notNilString.withCString { p in
			var c = 0
			while p[c] != 0 {
				c += 1
			}
			c += 1
			let alloced = UnsafeMutablePointer<Int8>.allocate(capacity: c)
			alloced.initialize(to: 0)
			for i in 0..<c {
				alloced[i] = p[i]
			}
			alloced[c-1] = 0
			ret = (alloced, c)
		}
		return ret
	}

	func cleanConvertedString(_ pair: (UnsafeMutablePointer<Int8>?, Int)) {
		if let p0 = pair.0 , pair.1 > 0 {
			p0.deinitialize(count: pair.1)
			p0.deallocate()
		}
	}

    /// Connects to a MySQL server
	public func connect(host hst: String? = nil, user: String? = nil, password: String? = nil, db: String? = nil, port: UInt32 = 0, socket: String? = nil, flag: UInt = 0) -> Bool {
		if self.ptr == nil {
			self.ptr = mysql_init(nil)
		}

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

    /// Selects a database
	public func selectDatabase(named namd: String) -> Bool {
		let r = mysql_select_db(self.ptr!, namd)
		return r == 0
	}

    /// Returns table names matching an optional simple regular expression in an array of Strings
	public func listTables(wildcard wild: String? = nil) -> [String] {
		var result = [String]()
		let res = (wild == nil ? mysql_list_tables(self.ptr!, nil) : mysql_list_tables(self.ptr!, wild!))
		if res != nil {
			var row = mysql_fetch_row(res)
			while row != nil {

			#if swift(>=3.0)
				if let tabPtr = row![0] {
					result.append(String(validatingUTF8: tabPtr) ?? "")
				}
			#else
				let tabPtr = row[0]
				if nil != tabPtr {
					result.append(String(validatingUTF8: tabPtr) ?? "")
				}
			#endif
				row = mysql_fetch_row(res)
			}
			mysql_free_result(res)
		}
		return result
	}

    /// Returns database names matching an optional simple regular expression in an array of Strings
	public func listDatabases(wildcard wild: String? = nil) -> [String] {
		var result = [String]()
		let res = wild == nil ? mysql_list_dbs(self.ptr!, nil) : mysql_list_dbs(self.ptr!, wild!)
		if res != nil {
			var row = mysql_fetch_row(res)
			while row != nil {

			#if swift(>=3.0)
				if let tabPtr = row![0] {
				result.append(String(validatingUTF8: tabPtr) ?? "")
				}
			#else
				let tabPtr = row[0]
				if nil != tabPtr {
					result.append(String(validatingUTF8: tabPtr) ?? "")
				}
			#endif
				row = mysql_fetch_row(res)
			}
			mysql_free_result(res)
		}
		return result
	}

    /// Commits the transaction
	public func commit() -> Bool {
		let r = mysql_commit(self.ptr!)
		return r == 1
	}

    /// Rolls back the transaction
	public func rollback() -> Bool {
		let r = mysql_rollback(self.ptr!)
		return r == 1
	}

    /// Checks whether any more results exist
	public func moreResults() -> Bool {
		let r = mysql_more_results(self.ptr!)
		return r == 1
	}

    /// Returns/initiates the next result in multiple-result executions
	public func nextResult() -> Int {
		let r = mysql_next_result(self.ptr!)
		return Int(r)
	}

    /// Executes an SQL query using the specified string
	public func query(statement stmt: String, multiple: Bool = false) -> Bool {
		if multiple {
			let r = mysql_query(self.ptr!, stmt)
			return r == 0
		} else {
			let r = mysql_real_query(self.ptr!, stmt, UInt(stmt.utf8.count))
			return r == 0
		}
	}

    /// Retrieves a complete result set to the client
    public func storeResults() -> MySQL.Results? {
	#if swift(>=3.0)
		guard let ret = mysql_store_result(self.ptr) else {
            return nil
        }
	#else
		let ret = mysql_store_result(self.ptr!)
		guard nil != ret else {
			return nil
		}
	#endif
		return MySQL.Results(ret)
	}

	#if os(Linux)
	func exposedOptionToMySQLOption(_ o: MySQLOpt) -> mysql_option {
		switch o {
		case MySQLOpt.MYSQL_OPT_CONNECT_TIMEOUT:
			return MYSQL_OPT_CONNECT_TIMEOUT
		case MySQLOpt.MYSQL_OPT_COMPRESS:
			return MYSQL_OPT_COMPRESS
		case MySQLOpt.MYSQL_OPT_NAMED_PIPE:
			return MYSQL_OPT_NAMED_PIPE
		case MySQLOpt.MYSQL_INIT_COMMAND:
			return MYSQL_INIT_COMMAND
		case MySQLOpt.MYSQL_READ_DEFAULT_FILE:
			return MYSQL_READ_DEFAULT_FILE
		case MySQLOpt.MYSQL_READ_DEFAULT_GROUP:
			return MYSQL_READ_DEFAULT_GROUP
		case MySQLOpt.MYSQL_SET_CHARSET_DIR:
			return MYSQL_SET_CHARSET_DIR
		case MySQLOpt.MYSQL_SET_CHARSET_NAME:
			return MYSQL_SET_CHARSET_NAME
		case MySQLOpt.MYSQL_OPT_LOCAL_INFILE:
			return MYSQL_OPT_LOCAL_INFILE
		case MySQLOpt.MYSQL_OPT_PROTOCOL:
			return MYSQL_OPT_PROTOCOL
		case MySQLOpt.MYSQL_SHARED_MEMORY_BASE_NAME:
			return MYSQL_SHARED_MEMORY_BASE_NAME
		case MySQLOpt.MYSQL_OPT_READ_TIMEOUT:
			return MYSQL_OPT_READ_TIMEOUT
		case MySQLOpt.MYSQL_OPT_WRITE_TIMEOUT:
			return MYSQL_OPT_WRITE_TIMEOUT
		case MySQLOpt.MYSQL_OPT_USE_RESULT:
			return MYSQL_OPT_USE_RESULT
		case MySQLOpt.MYSQL_OPT_USE_REMOTE_CONNECTION:
			return MYSQL_OPT_USE_REMOTE_CONNECTION
		case MySQLOpt.MYSQL_OPT_USE_EMBEDDED_CONNECTION:
			return MYSQL_OPT_USE_EMBEDDED_CONNECTION
		case MySQLOpt.MYSQL_OPT_GUESS_CONNECTION:
			return MYSQL_OPT_GUESS_CONNECTION
		case MySQLOpt.MYSQL_SET_CLIENT_IP:
			return MYSQL_SET_CLIENT_IP
		case MySQLOpt.MYSQL_SECURE_AUTH:
			return MYSQL_SECURE_AUTH
		case MySQLOpt.MYSQL_REPORT_DATA_TRUNCATION:
			return MYSQL_REPORT_DATA_TRUNCATION
		case MySQLOpt.MYSQL_OPT_RECONNECT:
			return MYSQL_OPT_RECONNECT
		case MySQLOpt.MYSQL_OPT_SSL_VERIFY_SERVER_CERT:
			return MYSQL_OPT_SSL_VERIFY_SERVER_CERT
		case MySQLOpt.MYSQL_PLUGIN_DIR:
			return MYSQL_PLUGIN_DIR
		case MySQLOpt.MYSQL_DEFAULT_AUTH:
			return MYSQL_DEFAULT_AUTH
		case MySQLOpt.MYSQL_OPT_BIND:
			return MYSQL_OPT_BIND
		case MySQLOpt.MYSQL_OPT_SSL_KEY:
			return MYSQL_OPT_SSL_KEY
		case MySQLOpt.MYSQL_OPT_SSL_CERT:
			return MYSQL_OPT_SSL_CERT
		case MySQLOpt.MYSQL_OPT_SSL_CA:
			return MYSQL_OPT_SSL_CA
		case MySQLOpt.MYSQL_OPT_SSL_CAPATH:
			return MYSQL_OPT_SSL_CAPATH
		case MySQLOpt.MYSQL_OPT_SSL_CIPHER:
			return MYSQL_OPT_SSL_CIPHER
		case MySQLOpt.MYSQL_OPT_SSL_CRL:
			return MYSQL_OPT_SSL_CRL
		case MySQLOpt.MYSQL_OPT_SSL_CRLPATH:
			return MYSQL_OPT_SSL_CRLPATH
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_RESET:
			return MYSQL_OPT_CONNECT_ATTR_RESET
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_ADD:
			return MYSQL_OPT_CONNECT_ATTR_ADD
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_DELETE:
			return MYSQL_OPT_CONNECT_ATTR_DELETE
///		case MySQLOpt.MYSQL_SERVER_PUBLIC_KEY:
///			return MYSQL_SERVER_PUBLIC_KEY
///		case MySQLOpt.MYSQL_ENABLE_CLEARTEXT_PLUGIN:
///			return MYSQL_ENABLE_CLEARTEXT_PLUGIN
///		case MySQLOpt.MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS:
///			return MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
		}
	}
	#else
	func exposedOptionToMySQLOption(_ o: MySQLOpt) -> mysql_option {
		switch o {
		case MySQLOpt.MYSQL_OPT_CONNECT_TIMEOUT:
			return MYSQL_OPT_CONNECT_TIMEOUT
		case MySQLOpt.MYSQL_OPT_COMPRESS:
			return MYSQL_OPT_COMPRESS
		case MySQLOpt.MYSQL_OPT_NAMED_PIPE:
			return MYSQL_OPT_NAMED_PIPE
		case MySQLOpt.MYSQL_INIT_COMMAND:
			return MYSQL_INIT_COMMAND
		case MySQLOpt.MYSQL_READ_DEFAULT_FILE:
			return MYSQL_READ_DEFAULT_FILE
		case MySQLOpt.MYSQL_READ_DEFAULT_GROUP:
			return MYSQL_READ_DEFAULT_GROUP
		case MySQLOpt.MYSQL_SET_CHARSET_DIR:
			return MYSQL_SET_CHARSET_DIR
		case MySQLOpt.MYSQL_SET_CHARSET_NAME:
			return MYSQL_SET_CHARSET_NAME
		case MySQLOpt.MYSQL_OPT_LOCAL_INFILE:
			return MYSQL_OPT_LOCAL_INFILE
		case MySQLOpt.MYSQL_OPT_PROTOCOL:
			return MYSQL_OPT_PROTOCOL
		case MySQLOpt.MYSQL_SHARED_MEMORY_BASE_NAME:
			return MYSQL_SHARED_MEMORY_BASE_NAME
		case MySQLOpt.MYSQL_OPT_READ_TIMEOUT:
			return MYSQL_OPT_READ_TIMEOUT
		case MySQLOpt.MYSQL_OPT_WRITE_TIMEOUT:
			return MYSQL_OPT_WRITE_TIMEOUT
		case MySQLOpt.MYSQL_OPT_USE_RESULT:
			return MYSQL_OPT_USE_RESULT
		case MySQLOpt.MYSQL_OPT_USE_REMOTE_CONNECTION:
			return MYSQL_OPT_USE_REMOTE_CONNECTION
		case MySQLOpt.MYSQL_OPT_USE_EMBEDDED_CONNECTION:
			return MYSQL_OPT_USE_EMBEDDED_CONNECTION
		case MySQLOpt.MYSQL_OPT_GUESS_CONNECTION:
			return MYSQL_OPT_GUESS_CONNECTION
		case MySQLOpt.MYSQL_SET_CLIENT_IP:
			return MYSQL_SET_CLIENT_IP
		case MySQLOpt.MYSQL_SECURE_AUTH:
			return MYSQL_SECURE_AUTH
		case MySQLOpt.MYSQL_REPORT_DATA_TRUNCATION:
			return MYSQL_REPORT_DATA_TRUNCATION
		case MySQLOpt.MYSQL_OPT_RECONNECT:
			return MYSQL_OPT_RECONNECT
		case MySQLOpt.MYSQL_OPT_SSL_VERIFY_SERVER_CERT:
			return MYSQL_OPT_SSL_VERIFY_SERVER_CERT
		case MySQLOpt.MYSQL_PLUGIN_DIR:
			return MYSQL_PLUGIN_DIR
		case MySQLOpt.MYSQL_DEFAULT_AUTH:
			return MYSQL_DEFAULT_AUTH
		case MySQLOpt.MYSQL_OPT_BIND:
			return MYSQL_OPT_BIND
		case MySQLOpt.MYSQL_OPT_SSL_KEY:
			return MYSQL_OPT_SSL_KEY
		case MySQLOpt.MYSQL_OPT_SSL_CERT:
			return MYSQL_OPT_SSL_CERT
		case MySQLOpt.MYSQL_OPT_SSL_CA:
			return MYSQL_OPT_SSL_CA
		case MySQLOpt.MYSQL_OPT_SSL_CAPATH:
			return MYSQL_OPT_SSL_CAPATH
		case MySQLOpt.MYSQL_OPT_SSL_CIPHER:
			return MYSQL_OPT_SSL_CIPHER
		case MySQLOpt.MYSQL_OPT_SSL_CRL:
			return MYSQL_OPT_SSL_CRL
		case MySQLOpt.MYSQL_OPT_SSL_CRLPATH:
			return MYSQL_OPT_SSL_CRLPATH
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_RESET:
			return MYSQL_OPT_CONNECT_ATTR_RESET
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_ADD:
			return MYSQL_OPT_CONNECT_ATTR_ADD
		case MySQLOpt.MYSQL_OPT_CONNECT_ATTR_DELETE:
			return MYSQL_OPT_CONNECT_ATTR_DELETE
		case MySQLOpt.MYSQL_SERVER_PUBLIC_KEY:
			return MYSQL_SERVER_PUBLIC_KEY
		case MySQLOpt.MYSQL_ENABLE_CLEARTEXT_PLUGIN:
			return MYSQL_ENABLE_CLEARTEXT_PLUGIN
///		case MySQLOpt.MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS:
///			return MYSQL_OPT_CAN_HANDLE_EXPIRED_PASSWORDS
		}
	}
		#endif

    /// Sets connect options for connect()
	public func setOption(_ option: MySQLOpt) -> Bool {
		return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), nil) == 0
	}

    /// Sets connect options for connect() with boolean option argument
	public func setOption(_ option: MySQLOpt, _ b: Bool) -> Bool {
		var myB = my_bool(b ? 1 : 0)
		return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), &myB) == 0
	}

    /// Sets connect options for connect() with integer option argument
	public func setOption(_ option: MySQLOpt, _ i: Int) -> Bool {
		var myI = UInt32(i)
		return mysql_options(self.ptr!, exposedOptionToMySQLOption(option), &myI) == 0
	}

    /// Sets connect options for connect() with string option argument
	public func setOption(_ option: MySQLOpt, _ s: String) -> Bool {
		var b = false
		s.withCString { p in
			b = mysql_options(self.ptr!, exposedOptionToMySQLOption(option), p) == 0
		}
		return b
	}

    /// Class used to manage and interact with result sets
	public final class Results: IteratorProtocol {
		var ptr: UnsafeMutablePointer<MYSQL_RES>?

		public typealias Element = [String?]

		init(_ ptr: UnsafeMutablePointer<MYSQL_RES>) {
			self.ptr = ptr
		}

		deinit {
			self.close()
		}

        /// close result set by releasing the results
		public func close() {
			if self.ptr != nil {
				mysql_free_result(self.ptr!)
				self.ptr = nil
			}
		}

        /// Seeks to an arbitrary row number in a query result set
		public func dataSeek(_ offset: UInt) {
			mysql_data_seek(self.ptr!, my_ulonglong(offset))
		}

        /// Returns the number of rows in a result set
		public func numRows() -> Int {
			return Int(mysql_num_rows(self.ptr!))
		}

        /// Returns the number of columns in a result set
        /// Returns: Int
		public func numFields() -> Int {
			return Int(mysql_num_fields(self.ptr!))
		}

        /// Fetches the next row from the result set
        ///     returning a String array of column names if row available
        /// Returns: optional Element
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
					let s = raw.withMemoryRebound(to: UInt8.self, capacity: len) { UTF8Encoding.encode(generator: GenerateFromPointer(from: $0, count: len)) }
					ret.append(s)
                } else {
                    ret.append(nil)
                }
			}
			return ret
		}

        /// passes a string array of the column names to the callback provided
		public func forEachRow(callback: (Element) -> ()) {
			while let element = self.next() {
				callback(element)
			}
		}
	}
}

