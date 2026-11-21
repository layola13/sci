const std = @import("std");

pub const SA_STD_ABI_VERSION: u32 = 1;

pub const SA_STD_OK: i32 = 0;

pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;

pub const SA_STD_ERR_INVALID_HANDLE: i32 = 2;

pub const SA_STD_ERR_NOT_FOUND: i32 = 3;

pub const SA_STD_ERR_ACCESS: i32 = 4;

pub const SA_STD_ERR_NO_MEMORY: i32 = 5;

pub const SA_STD_ERR_IO: i32 = 6;

pub const SA_STD_ERR_NET: i32 = 7;

pub const SA_STD_ERR_UNSUPPORTED: i32 = 8;

pub const SA_STD_ERR_TRUNCATED: i32 = 9;

pub const SA_STD_ERR_PERMISSION_DENIED: i32 = 10;

pub const SA_STD_ERR_ALREADY_EXISTS: i32 = 11;

pub const SA_STD_ERR_UNKNOWN: i32 = 127;

pub const SA_NET_IOV_MAX: usize = 1024;

pub const SA_STD_STDIN: u64 = 1;

pub const SA_STD_STDOUT: u64 = 2;

pub const SA_STD_STDERR: u64 = 3;

pub const SA_FS_FILE_REGULAR: u32 = 1;

pub const SA_FS_FILE_DIR: u32 = 2;

pub const SA_FS_FILE_SYMLINK: u32 = 3;

pub const SA_FS_FILE_OTHER: u32 = 255;

pub const SA_JSON_KIND_INVALID: u32 = std.math.maxInt(u32);

pub const SA_JSON_KIND_NULL: u32 = 0;

pub const SA_JSON_KIND_BOOL: u32 = 1;

pub const SA_JSON_KIND_INTEGER: u32 = 2;

pub const SA_JSON_KIND_FLOAT: u32 = 3;

pub const SA_JSON_KIND_NUMBER_STRING: u32 = 4;

pub const SA_JSON_KIND_STRING: u32 = 5;

pub const SA_JSON_KIND_ARRAY: u32 = 6;

pub const SA_JSON_KIND_OBJECT: u32 = 7;

pub const SA_JSON_TOKEN_INVALID: u32 = std.math.maxInt(u32);

pub const SA_JSON_TOKEN_OBJECT_BEGIN: u32 = 0;

pub const SA_JSON_TOKEN_OBJECT_END: u32 = 1;

pub const SA_JSON_TOKEN_ARRAY_BEGIN: u32 = 2;

pub const SA_JSON_TOKEN_ARRAY_END: u32 = 3;

pub const SA_JSON_TOKEN_TRUE: u32 = 4;

pub const SA_JSON_TOKEN_FALSE: u32 = 5;

pub const SA_JSON_TOKEN_NULL: u32 = 6;

pub const SA_JSON_TOKEN_NUMBER: u32 = 7;

pub const SA_JSON_TOKEN_PARTIAL_NUMBER: u32 = 8;

pub const SA_JSON_TOKEN_STRING: u32 = 9;

pub const SA_JSON_TOKEN_PARTIAL_STRING: u32 = 10;

pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1: u32 = 11;

pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2: u32 = 12;

pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3: u32 = 13;

pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4: u32 = 14;

pub const SA_JSON_TOKEN_END_OF_DOCUMENT: u32 = 15;

pub const SA_JSON_TOKEN_ALLOCATED_NUMBER: u32 = 16;

pub const SA_JSON_TOKEN_ALLOCATED_STRING: u32 = 17;

pub const SA_JSON_WHITESPACE_MINIFIED: u32 = 0;

pub const SA_JSON_WHITESPACE_INDENT_1: u32 = 1;

pub const SA_JSON_WHITESPACE_INDENT_2: u32 = 2;

pub const SA_JSON_WHITESPACE_INDENT_3: u32 = 3;

pub const SA_JSON_WHITESPACE_INDENT_4: u32 = 4;

pub const SA_JSON_WHITESPACE_INDENT_8: u32 = 5;

pub const SA_JSON_WHITESPACE_INDENT_TAB: u32 = 6;

pub const SA_REGEX_EXTENDED: c_int = 1;

pub const SA_REGEX_ICASE: c_int = 2;

pub const SA_REGEX_NEWLINE: c_int = 4;

pub const SA_REGEX_NOSUB: c_int = 8;

pub const SA_REGEX_NOTBOL: c_int = 1;

pub const SA_REGEX_NOTEOL: c_int = 2;

pub const SA_REGEX_STARTEND: c_int = 4;

pub const SA_REGEX_REG_NOERROR: c_int = 0;

pub const SA_REGEX_REG_OK: c_int = 0;

pub const SA_REGEX_REG_NOMATCH: c_int = 1;

pub const SA_REGEX_REG_BADPAT: c_int = 2;

pub const SA_REGEX_REG_ECOLLATE: c_int = 3;

pub const SA_REGEX_REG_ECTYPE: c_int = 4;

pub const SA_REGEX_REG_EESCAPE: c_int = 5;

pub const SA_REGEX_REG_ESUBREG: c_int = 6;

pub const SA_REGEX_REG_EBRACK: c_int = 7;

pub const SA_REGEX_REG_EPAREN: c_int = 8;

pub const SA_REGEX_REG_EBRACE: c_int = 9;

pub const SA_REGEX_REG_BADBR: c_int = 10;

pub const SA_REGEX_REG_ERANGE: c_int = 11;

pub const SA_REGEX_REG_ESPACE: c_int = 12;

pub const SA_REGEX_REG_BADRPT: c_int = 13;

pub const SA_REGEX_REG_ENOSYS: c_int = -1;

pub const SA_NET_UNIX_ADDR_UNNAMED: u32 = 0;

pub const SA_NET_UNIX_ADDR_PATHNAME: u32 = 1;

pub const SA_NET_UNIX_ADDR_ABSTRACT: u32 = 2;

pub const SA_STD_NET_POLL_READ: u32 = 1;

pub const SA_STD_NET_POLL_WRITE: u32 = 2;

pub const SA_STD_NET_POLL_ERROR: u32 = 4;

pub const SA_STD_NET_POLL_MAX_HANDLES: u64 = 4096;
