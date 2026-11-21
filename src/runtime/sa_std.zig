const std = @import("std");
pub const spawn = @import("sa_std/spawn.zig");
pub const policy = @import("sa_std/policy.zig");
test "sa_std_tests" { std.testing.refAllDecls(@import("sa_std/sa_std_tests.zig")); }
test "sa_std_tests_net" { std.testing.refAllDecls(@import("sa_std/tests_net.zig")); }
test "sa_std_tests_codec" { std.testing.refAllDecls(@import("sa_std/tests_codec.zig")); }
pub const builtin = @import("builtin");
pub const sio = @import("sio");

// Runtime permission policy core (sala 16_policy phase 1): pure decision
// logic, referenced here so the module and its unit tests join every
// sa_std build/test graph. Interception wiring lands separately.
pub const sa_policy = @import("sa_policy.zig");
pub const sa_globals = @import("sa_globals.zig");
// Goroutine runtime: the native stack-switching implementation
// everywhere except wasm, where the cooperative CPS/state-machine
// runtime (sa_task_coop.zig) provides the same task.sai extern
// surface — the native mechanism cannot lower to wasm.
pub const sa_task = if (is_wasm) @import("sa_task_coop.zig") else @import("sa_task.zig");

// Goroutine netpoller glue: sa_task declares sa_std_net_poll_wait
// as a plain extern and this module's export below satisfies it
// in the same compilation. (An .init_array registration was
// tried and removed: SA-built binaries segfault at startup when
// the archive carries an .init_array entry — see sa_task.zig.)
pub const sa_identity = @import("sa_identity.zig");

// Re-exports: decls moved to sa_std/* submodules (grouped by module).
// --- sa_std/b64_simd.zig ---
pub const b64SimdSextetVal = @import("sa_std/b64_simd.zig").b64SimdSextetVal; pub const sa_b64dec_simd = @import("sa_std/b64_simd.zig").sa_b64dec_simd;
// --- sa_std/chat_fallback.zig ---
pub const jsonBoolValue = @import("sa_std/chat_fallback.zig").jsonBoolValue; pub const appendJsonFieldName = @import("sa_std/chat_fallback.zig").appendJsonFieldName; pub const appendSystemText = @import("sa_std/chat_fallback.zig").appendSystemText; pub const responseContentTextOnlyAlloc = @import("sa_std/chat_fallback.zig").responseContentTextOnlyAlloc; pub const appendMappedResponseContentPart = @import("sa_std/chat_fallback.zig").appendMappedResponseContentPart; pub const appendResponseContentAsChat = @import("sa_std/chat_fallback.zig").appendResponseContentAsChat; pub const isResponsesToolCallType = @import("sa_std/chat_fallback.zig").isResponsesToolCallType; pub const isResponsesToolOutputType = @import("sa_std/chat_fallback.zig").isResponsesToolOutputType;
pub const responseToolCallNameForChat = @import("sa_std/chat_fallback.zig").responseToolCallNameForChat; pub const collectResponseToolCallNames = @import("sa_std/chat_fallback.zig").collectResponseToolCallNames; pub const appendChatMessagePrefix = @import("sa_std/chat_fallback.zig").appendChatMessagePrefix; pub const appendResponseMessageAsChat = @import("sa_std/chat_fallback.zig").appendResponseMessageAsChat; pub const appendResponseToolCallAsChat = @import("sa_std/chat_fallback.zig").appendResponseToolCallAsChat; pub const appendResponseToolOutputAsChat = @import("sa_std/chat_fallback.zig").appendResponseToolOutputAsChat; pub const appendNormalizedChatTool = @import("sa_std/chat_fallback.zig").appendNormalizedChatTool; pub const appendNormalizedChatToolsField = @import("sa_std/chat_fallback.zig").appendNormalizedChatToolsField;
pub const appendResponseFormatFromText = @import("sa_std/chat_fallback.zig").appendResponseFormatFromText; pub const shouldSkipResponsesFallbackField = @import("sa_std/chat_fallback.zig").shouldSkipResponsesFallbackField; pub const denoResponsesChatFallbackRequest = @import("sa_std/chat_fallback.zig").denoResponsesChatFallbackRequest;
// --- sa_std/chat_norm.zig ---
pub const longestSuffixPrefix = @import("sa_std/chat_norm.zig").longestSuffixPrefix; pub const ThoughtStreamSplitter = @import("sa_std/chat_norm.zig").ThoughtStreamSplitter; pub const jsonU64Value = @import("sa_std/chat_norm.zig").jsonU64Value; pub const appendResponseCreated = @import("sa_std/chat_norm.zig").appendResponseCreated; pub const appendReasoningDelta = @import("sa_std/chat_norm.zig").appendReasoningDelta; pub const appendReasoningDone = @import("sa_std/chat_norm.zig").appendReasoningDone; pub const appendMessageDelta = @import("sa_std/chat_norm.zig").appendMessageDelta; pub const appendMessageDone = @import("sa_std/chat_norm.zig").appendMessageDone;
pub const requestAllowsContinuation = @import("sa_std/chat_norm.zig").requestAllowsContinuation; pub const isProgressOnlyText = @import("sa_std/chat_norm.zig").isProgressOnlyText; pub const appendContinuationTool = @import("sa_std/chat_norm.zig").appendContinuationTool; pub const appendContinuationToolJson = @import("sa_std/chat_norm.zig").appendContinuationToolJson; pub const ChatToolCallState = @import("sa_std/chat_norm.zig").ChatToolCallState; pub const shellQuote = @import("sa_std/chat_norm.zig").shellQuote; pub const isSensitiveEnvPath = @import("sa_std/chat_norm.zig").isSensitiveEnvPath; pub const appendCommandArguments = @import("sa_std/chat_norm.zig").appendCommandArguments;
pub const appendReadCommand = @import("sa_std/chat_norm.zig").appendReadCommand; pub const splitMcpNamespace = @import("sa_std/chat_norm.zig").splitMcpNamespace; pub const denormalizeMcpServerNameAlloc = @import("sa_std/chat_norm.zig").denormalizeMcpServerNameAlloc; pub const requestMentionsTool = @import("sa_std/chat_norm.zig").requestMentionsTool; pub const normalizeChatToolArguments = @import("sa_std/chat_norm.zig").normalizeChatToolArguments; pub const appendNormalizedToolCall = @import("sa_std/chat_norm.zig").appendNormalizedToolCall; pub const appendNormalizedToolCallJson = @import("sa_std/chat_norm.zig").appendNormalizedToolCallJson; pub const findToolCallState = @import("sa_std/chat_norm.zig").findToolCallState;
pub const parseToolCallIndex = @import("sa_std/chat_norm.zig").parseToolCallIndex; pub const appendResponseDone = @import("sa_std/chat_norm.zig").appendResponseDone; pub const appendChatUsageJson = @import("sa_std/chat_norm.zig").appendChatUsageJson; pub const appendChatJsonReasoningItem = @import("sa_std/chat_norm.zig").appendChatJsonReasoningItem; pub const appendChatJsonMessageItem = @import("sa_std/chat_norm.zig").appendChatJsonMessageItem; pub const appendOutputComma = @import("sa_std/chat_norm.zig").appendOutputComma; pub const denoChatJsonToResponses = @import("sa_std/chat_norm.zig").denoChatJsonToResponses; pub const ThoughtSplit = @import("sa_std/chat_norm.zig").ThoughtSplit;
pub const splitThoughtTextAlloc = @import("sa_std/chat_norm.zig").splitThoughtTextAlloc; pub const appendMergedReasoningText = @import("sa_std/chat_norm.zig").appendMergedReasoningText; pub const appendReasoningFields = @import("sa_std/chat_norm.zig").appendReasoningFields; pub const isNativeReasoningType = @import("sa_std/chat_norm.zig").isNativeReasoningType; pub const appendNativeReasoningItem = @import("sa_std/chat_norm.zig").appendNativeReasoningItem; pub const appendNativeMessageItem = @import("sa_std/chat_norm.zig").appendNativeMessageItem; pub const appendNativeNormalizedOutput = @import("sa_std/chat_norm.zig").appendNativeNormalizedOutput; pub const nativeResponsesJsonNeedsNormalize = @import("sa_std/chat_norm.zig").nativeResponsesJsonNeedsNormalize;
pub const denoResponsesJsonNormalize = @import("sa_std/chat_norm.zig").denoResponsesJsonNormalize; pub const jsonArrayFirst = @import("sa_std/chat_norm.zig").jsonArrayFirst; pub const normalizeResponsesArgumentsString = @import("sa_std/chat_norm.zig").normalizeResponsesArgumentsString; pub const normalizeResponsesEventData = @import("sa_std/chat_norm.zig").normalizeResponsesEventData; pub const appendNormalizedResponsesSseBlock = @import("sa_std/chat_norm.zig").appendNormalizedResponsesSseBlock; pub const denoResponsesSseNormalize = @import("sa_std/chat_norm.zig").denoResponsesSseNormalize; pub const appendChatSseDataChunk = @import("sa_std/chat_norm.zig").appendChatSseDataChunk; pub const denoChatSseToResponses = @import("sa_std/chat_norm.zig").denoChatSseToResponses;
// --- sa_std/consts.zig ---
pub const SA_STD_ABI_VERSION = @import("sa_std/consts.zig").SA_STD_ABI_VERSION; pub const SA_STD_OK = @import("sa_std/consts.zig").SA_STD_OK; pub const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_std/consts.zig").SA_STD_ERR_INVALID_ARGUMENT; pub const SA_STD_ERR_INVALID_HANDLE = @import("sa_std/consts.zig").SA_STD_ERR_INVALID_HANDLE; pub const SA_STD_ERR_NOT_FOUND = @import("sa_std/consts.zig").SA_STD_ERR_NOT_FOUND; pub const SA_STD_ERR_ACCESS = @import("sa_std/consts.zig").SA_STD_ERR_ACCESS; pub const SA_STD_ERR_NO_MEMORY = @import("sa_std/consts.zig").SA_STD_ERR_NO_MEMORY; pub const SA_STD_ERR_IO = @import("sa_std/consts.zig").SA_STD_ERR_IO;
pub const SA_STD_ERR_NET = @import("sa_std/consts.zig").SA_STD_ERR_NET; pub const SA_STD_ERR_UNSUPPORTED = @import("sa_std/consts.zig").SA_STD_ERR_UNSUPPORTED; pub const SA_STD_ERR_TRUNCATED = @import("sa_std/consts.zig").SA_STD_ERR_TRUNCATED; pub const SA_STD_ERR_PERMISSION_DENIED = @import("sa_std/consts.zig").SA_STD_ERR_PERMISSION_DENIED; pub const SA_STD_ERR_ALREADY_EXISTS = @import("sa_std/consts.zig").SA_STD_ERR_ALREADY_EXISTS; pub const SA_STD_ERR_UNKNOWN = @import("sa_std/consts.zig").SA_STD_ERR_UNKNOWN; pub const SA_NET_IOV_MAX = @import("sa_std/consts.zig").SA_NET_IOV_MAX; pub const SA_STD_STDIN = @import("sa_std/consts.zig").SA_STD_STDIN;
pub const SA_STD_STDOUT = @import("sa_std/consts.zig").SA_STD_STDOUT; pub const SA_STD_STDERR = @import("sa_std/consts.zig").SA_STD_STDERR; pub const SA_FS_FILE_REGULAR = @import("sa_std/consts.zig").SA_FS_FILE_REGULAR; pub const SA_FS_FILE_DIR = @import("sa_std/consts.zig").SA_FS_FILE_DIR; pub const SA_FS_FILE_SYMLINK = @import("sa_std/consts.zig").SA_FS_FILE_SYMLINK; pub const SA_FS_FILE_OTHER = @import("sa_std/consts.zig").SA_FS_FILE_OTHER; pub const SA_JSON_KIND_INVALID = @import("sa_std/consts.zig").SA_JSON_KIND_INVALID; pub const SA_JSON_KIND_NULL = @import("sa_std/consts.zig").SA_JSON_KIND_NULL;
pub const SA_JSON_KIND_BOOL = @import("sa_std/consts.zig").SA_JSON_KIND_BOOL; pub const SA_JSON_KIND_INTEGER = @import("sa_std/consts.zig").SA_JSON_KIND_INTEGER; pub const SA_JSON_KIND_FLOAT = @import("sa_std/consts.zig").SA_JSON_KIND_FLOAT; pub const SA_JSON_KIND_NUMBER_STRING = @import("sa_std/consts.zig").SA_JSON_KIND_NUMBER_STRING; pub const SA_JSON_KIND_STRING = @import("sa_std/consts.zig").SA_JSON_KIND_STRING; pub const SA_JSON_KIND_ARRAY = @import("sa_std/consts.zig").SA_JSON_KIND_ARRAY; pub const SA_JSON_KIND_OBJECT = @import("sa_std/consts.zig").SA_JSON_KIND_OBJECT; pub const SA_JSON_TOKEN_INVALID = @import("sa_std/consts.zig").SA_JSON_TOKEN_INVALID;
pub const SA_JSON_TOKEN_OBJECT_BEGIN = @import("sa_std/consts.zig").SA_JSON_TOKEN_OBJECT_BEGIN; pub const SA_JSON_TOKEN_OBJECT_END = @import("sa_std/consts.zig").SA_JSON_TOKEN_OBJECT_END; pub const SA_JSON_TOKEN_ARRAY_BEGIN = @import("sa_std/consts.zig").SA_JSON_TOKEN_ARRAY_BEGIN; pub const SA_JSON_TOKEN_ARRAY_END = @import("sa_std/consts.zig").SA_JSON_TOKEN_ARRAY_END; pub const SA_JSON_TOKEN_TRUE = @import("sa_std/consts.zig").SA_JSON_TOKEN_TRUE; pub const SA_JSON_TOKEN_FALSE = @import("sa_std/consts.zig").SA_JSON_TOKEN_FALSE; pub const SA_JSON_TOKEN_NULL = @import("sa_std/consts.zig").SA_JSON_TOKEN_NULL; pub const SA_JSON_TOKEN_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_NUMBER;
pub const SA_JSON_TOKEN_PARTIAL_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_NUMBER; pub const SA_JSON_TOKEN_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_STRING; pub const SA_JSON_TOKEN_PARTIAL_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING; pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1; pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2; pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3; pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4; pub const SA_JSON_TOKEN_END_OF_DOCUMENT = @import("sa_std/consts.zig").SA_JSON_TOKEN_END_OF_DOCUMENT;
pub const SA_JSON_TOKEN_ALLOCATED_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_ALLOCATED_NUMBER; pub const SA_JSON_TOKEN_ALLOCATED_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_ALLOCATED_STRING; pub const SA_JSON_WHITESPACE_MINIFIED = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_MINIFIED; pub const SA_JSON_WHITESPACE_INDENT_1 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_1; pub const SA_JSON_WHITESPACE_INDENT_2 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_2; pub const SA_JSON_WHITESPACE_INDENT_3 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_3; pub const SA_JSON_WHITESPACE_INDENT_4 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_4; pub const SA_JSON_WHITESPACE_INDENT_8 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_8;
pub const SA_JSON_WHITESPACE_INDENT_TAB = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_TAB; pub const SA_REGEX_EXTENDED = @import("sa_std/consts.zig").SA_REGEX_EXTENDED; pub const SA_REGEX_ICASE = @import("sa_std/consts.zig").SA_REGEX_ICASE; pub const SA_REGEX_NEWLINE = @import("sa_std/consts.zig").SA_REGEX_NEWLINE; pub const SA_REGEX_NOSUB = @import("sa_std/consts.zig").SA_REGEX_NOSUB; pub const SA_REGEX_NOTBOL = @import("sa_std/consts.zig").SA_REGEX_NOTBOL; pub const SA_REGEX_NOTEOL = @import("sa_std/consts.zig").SA_REGEX_NOTEOL; pub const SA_REGEX_STARTEND = @import("sa_std/consts.zig").SA_REGEX_STARTEND;
pub const SA_REGEX_REG_NOERROR = @import("sa_std/consts.zig").SA_REGEX_REG_NOERROR; pub const SA_REGEX_REG_OK = @import("sa_std/consts.zig").SA_REGEX_REG_OK; pub const SA_REGEX_REG_NOMATCH = @import("sa_std/consts.zig").SA_REGEX_REG_NOMATCH; pub const SA_REGEX_REG_BADPAT = @import("sa_std/consts.zig").SA_REGEX_REG_BADPAT; pub const SA_REGEX_REG_ECOLLATE = @import("sa_std/consts.zig").SA_REGEX_REG_ECOLLATE; pub const SA_REGEX_REG_ECTYPE = @import("sa_std/consts.zig").SA_REGEX_REG_ECTYPE; pub const SA_REGEX_REG_EESCAPE = @import("sa_std/consts.zig").SA_REGEX_REG_EESCAPE; pub const SA_REGEX_REG_ESUBREG = @import("sa_std/consts.zig").SA_REGEX_REG_ESUBREG;
pub const SA_REGEX_REG_EBRACK = @import("sa_std/consts.zig").SA_REGEX_REG_EBRACK; pub const SA_REGEX_REG_EPAREN = @import("sa_std/consts.zig").SA_REGEX_REG_EPAREN; pub const SA_REGEX_REG_EBRACE = @import("sa_std/consts.zig").SA_REGEX_REG_EBRACE; pub const SA_REGEX_REG_BADBR = @import("sa_std/consts.zig").SA_REGEX_REG_BADBR; pub const SA_REGEX_REG_ERANGE = @import("sa_std/consts.zig").SA_REGEX_REG_ERANGE; pub const SA_REGEX_REG_ESPACE = @import("sa_std/consts.zig").SA_REGEX_REG_ESPACE; pub const SA_REGEX_REG_BADRPT = @import("sa_std/consts.zig").SA_REGEX_REG_BADRPT; pub const SA_REGEX_REG_ENOSYS = @import("sa_std/consts.zig").SA_REGEX_REG_ENOSYS;
pub const SA_NET_UNIX_ADDR_UNNAMED = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_UNNAMED; pub const SA_NET_UNIX_ADDR_PATHNAME = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_PATHNAME; pub const SA_NET_UNIX_ADDR_ABSTRACT = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_ABSTRACT; pub const SA_STD_NET_POLL_READ = @import("sa_std/consts.zig").SA_STD_NET_POLL_READ; pub const SA_STD_NET_POLL_WRITE = @import("sa_std/consts.zig").SA_STD_NET_POLL_WRITE; pub const SA_STD_NET_POLL_ERROR = @import("sa_std/consts.zig").SA_STD_NET_POLL_ERROR; pub const SA_STD_NET_POLL_MAX_HANDLES = @import("sa_std/consts.zig").SA_STD_NET_POLL_MAX_HANDLES;
// --- sa_std/core_export.zig ---
pub const sa_std_version = @import("sa_std/core_export.zig").sa_std_version; pub const sa_num_add_checked = @import("sa_std/core_export.zig").sa_num_add_checked; pub const sa_num_sub_checked = @import("sa_std/core_export.zig").sa_num_sub_checked; pub const sa_num_mul_checked = @import("sa_std/core_export.zig").sa_num_mul_checked; pub const sa_std_last_error = @import("sa_std/core_export.zig").sa_std_last_error; pub const sa_std_stdin = @import("sa_std/core_export.zig").sa_std_stdin; pub const sa_std_stdout = @import("sa_std/core_export.zig").sa_std_stdout; pub const sa_std_stderr = @import("sa_std/core_export.zig").sa_std_stderr;
pub const sa_std_print = @import("sa_std/core_export.zig").sa_std_print; pub const sa_unicode_normalize = @import("sa_std/core_export.zig").sa_unicode_normalize; pub const sa_host_is_bun = @import("sa_std/core_export.zig").sa_host_is_bun; pub const sa_std_fd_from_raw = @import("sa_std/core_export.zig").sa_std_fd_from_raw; pub const sa_std_fd_close_raw = @import("sa_std/core_export.zig").sa_std_fd_close_raw; pub const sa_thread_current_id = @import("sa_std/core_export.zig").sa_thread_current_id; pub const sa_thread_yield_now = @import("sa_std/core_export.zig").sa_thread_yield_now; pub const sa_parse_float = @import("sa_std/core_export.zig").sa_parse_float;
pub const sa_mem_free = @import("sa_std/core_export.zig").sa_mem_free; pub const sa_print_bytes = @import("sa_std/core_export.zig").sa_print_bytes;
// --- sa_std/core_misc.zig ---
pub const Ipv6MreqC = @import("sa_std/core_misc.zig").Ipv6MreqC; pub const addressSocketText = @import("sa_std/core_misc.zig").addressSocketText; pub const acquireJsonWriterForWrite = @import("sa_std/core_misc.zig").acquireJsonWriterForWrite; pub const SaProcessArgv = @import("sa_std/core_misc.zig").SaProcessArgv; pub const mapError = @import("sa_std/core_misc.zig").mapError; pub const fillUtcNow = @import("sa_std/core_misc.zig").fillUtcNow; pub const monotonicNowNs = @import("sa_std/core_misc.zig").monotonicNowNs; pub const makeIpv6Membership = @import("sa_std/core_misc.zig").makeIpv6Membership;
pub const applyRawMode = @import("sa_std/core_misc.zig").applyRawMode; pub const lockRegistry = @import("sa_std/core_misc.zig").lockRegistry; pub const udpSocketFd = @import("sa_std/core_misc.zig").udpSocketFd; pub const statusFromTerm = @import("sa_std/core_misc.zig").statusFromTerm; pub const argvFromBlob = @import("sa_std/core_misc.zig").argvFromBlob; pub const argvFromEntries = @import("sa_std/core_misc.zig").argvFromEntries; pub const waitStatusFromSiginfo = @import("sa_std/core_misc.zig").waitStatusFromSiginfo; pub const sendSignalToProcessGroup = @import("sa_std/core_misc.zig").sendSignalToProcessGroup;
pub const errnoToSetupError = @import("sa_std/core_misc.zig").errnoToSetupError; pub const netGetAddressList = @import("sa_std/core_misc.zig").netGetAddressList; pub const processArgsJsonAlloc = @import("sa_std/core_misc.zig").processArgsJsonAlloc; pub const unicodeNormalizerForForm = @import("sa_std/core_misc.zig").unicodeNormalizerForForm; pub const CivilParts = @import("sa_std/core_misc.zig").CivilParts; pub const civilParts = @import("sa_std/core_misc.zig").civilParts; pub const signal = @import("sa_std/core_misc.zig").signal; pub const sa_hmac_sha256_hex = @import("sa_std/core_misc.zig").sa_hmac_sha256_hex;
pub const sa_hmac_sha1_hex = @import("sa_std/core_misc.zig").sa_hmac_sha1_hex;
// --- sa_std/core_misc2.zig ---
pub const RegexC = @import("sa_std/core_misc2.zig").RegexC; pub const IpMreqC = @import("sa_std/core_misc2.zig").IpMreqC; pub const fbsd_utsname = @import("sa_std/core_misc2.zig").fbsd_utsname; pub const SaPluginDescriptor = @import("sa_std/core_misc2.zig").SaPluginDescriptor; pub const SaJsonToken = @import("sa_std/core_misc2.zig").SaJsonToken; pub const SaJsonStringifyOptions = @import("sa_std/core_misc2.zig").SaJsonStringifyOptions; pub const SaNetAddr = @import("sa_std/core_misc2.zig").SaNetAddr; pub const TimespecSec = @import("sa_std/core_misc2.zig").TimespecSec;
pub const TimespecNsec = @import("sa_std/core_misc2.zig").TimespecNsec; pub const SaTermWinsize = @import("sa_std/core_misc2.zig").SaTermWinsize; pub const compatibility_mmap_page = @import("sa_std/core_misc2.zig").compatibility_mmap_page; pub const compatibility_dlsym_cookie = @import("sa_std/core_misc2.zig").compatibility_dlsym_cookie; pub const mutBytes = @import("sa_std/core_misc2.zig").mutBytes; pub const pathBytes = @import("sa_std/core_misc2.zig").pathBytes; pub const makeIpv4Membership = @import("sa_std/core_misc2.zig").makeIpv4Membership; pub const daysFromCivil = @import("sa_std/core_misc2.zig").daysFromCivil;
pub const fd_open = @import("sa_std/core_misc2.zig").fd_open; pub const fd_read = @import("sa_std/core_misc2.zig").fd_read; pub const fd_close = @import("sa_std/core_misc2.zig").fd_close; pub const mmap = @import("sa_std/core_misc2.zig").mmap; pub const munmap = @import("sa_std/core_misc2.zig").munmap; pub const dlsym = @import("sa_std/core_misc2.zig").dlsym; pub const timespecFromUnixMs = @import("sa_std/core_misc2.zig").timespecFromUnixMs; pub const tilePad = @import("sa_std/core_misc2.zig").tilePad;
pub const sa_crypto_random_bytes = @import("sa_std/core_misc2.zig").sa_crypto_random_bytes;
// --- sa_std/core_misc3.zig ---
pub const saStdPolicyAllowsRun = @import("sa_std/core_misc3.zig").saStdPolicyAllowsRun; pub const saStdPolicyAllowsFsRead = @import("sa_std/core_misc3.zig").saStdPolicyAllowsFsRead; pub const policyEnvOwned = @import("sa_std/core_misc3.zig").policyEnvOwned; pub const SOLT = @import("sa_std/core_misc3.zig").SOLT; pub const RegexMatchC = @import("sa_std/core_misc3.zig").RegexMatchC; pub const markJsonWriterValueComplete = @import("sa_std/core_misc3.zig").markJsonWriterValueComplete; pub const SaTermEpollEvent = @import("sa_std/core_misc3.zig").SaTermEpollEvent; pub const lingerSeconds = @import("sa_std/core_misc3.zig").lingerSeconds;
pub const LinuxUCred = @import("sa_std/core_misc3.zig").LinuxUCred; pub const armPeerCredHarvest = @import("sa_std/core_misc3.zig").armPeerCredHarvest; pub const libcErrRc = @import("sa_std/core_misc3.zig").libcErrRc; pub const libcUsize = @import("sa_std/core_misc3.zig").libcUsize; pub const EnvVarJson = @import("sa_std/core_misc3.zig").EnvVarJson; pub const saNumCheckedTrap = @import("sa_std/core_misc3.zig").saNumCheckedTrap; pub const weekdayNames = @import("sa_std/core_misc3.zig").weekdayNames; pub const groupId = @import("sa_std/core_misc3.zig").groupId;
pub const recv_msg_flag_pktinfo = @import("sa_std/core_misc3.zig").recv_msg_flag_pktinfo; pub const recv_msg_flag_timestamp = @import("sa_std/core_misc3.zig").recv_msg_flag_timestamp; pub const recv_msg_flag_ctrunc = @import("sa_std/core_misc3.zig").recv_msg_flag_ctrunc; pub const recv_msg_flag_trunc = @import("sa_std/core_misc3.zig").recv_msg_flag_trunc; pub const expectTimeoutRoundedUpWithin = @import("sa_std/core_misc3.zig").expectTimeoutRoundedUpWithin;
// --- sa_std/core_types.zig ---
pub const SO_MARK = @import("sa_std/core_types.zig").SO_MARK; pub const RegexHandle = @import("sa_std/core_types.zig").RegexHandle; pub const NetAddress = @import("sa_std/core_types.zig").NetAddress; pub const NetAddressList = @import("sa_std/core_types.zig").NetAddressList; pub const stringConcat = @import("sa_std/core_types.zig").stringConcat; pub const dlclose = @import("sa_std/core_types.zig").dlclose; pub const ProcessOutputStream = @import("sa_std/core_types.zig").ProcessOutputStream; pub const metadataModeMatches = @import("sa_std/core_types.zig").metadataModeMatches;
pub const poll_wait_stack_handles = @import("sa_std/core_types.zig").poll_wait_stack_handles; pub const recv_multi_max_msgs = @import("sa_std/core_types.zig").recv_multi_max_msgs; pub const isAsciiWhitespace = @import("sa_std/core_types.zig").isAsciiWhitespace;
// --- sa_std/core_util.zig ---
pub const tcp_nodelay = @import("sa_std/core_util.zig").tcp_nodelay; pub const registerNetAddrList = @import("sa_std/core_util.zig").registerNetAddrList; pub const registerNetAddrOutLocked = @import("sa_std/core_util.zig").registerNetAddrOutLocked; pub const finish = @import("sa_std/core_util.zig").finish; pub const finishErr = @import("sa_std/core_util.zig").finishErr; pub const setSocketOptBool = @import("sa_std/core_util.zig").setSocketOptBool; pub const setSocketOptInt = @import("sa_std/core_util.zig").setSocketOptInt; pub const setSocketOptU32 = @import("sa_std/core_util.zig").setSocketOptU32;
pub const setSocketOptByte = @import("sa_std/core_util.zig").setSocketOptByte; pub const setSocketOptBytes = @import("sa_std/core_util.zig").setSocketOptBytes; pub const setSocketOptLinger = @import("sa_std/core_util.zig").setSocketOptLinger; pub const getSocketOptLinger = @import("sa_std/core_util.zig").getSocketOptLinger; pub const getSocketOptInt = @import("sa_std/core_util.zig").getSocketOptInt; pub const getSocketOptByte = @import("sa_std/core_util.zig").getSocketOptByte; pub const getSocketOptU32 = @import("sa_std/core_util.zig").getSocketOptU32; pub const getSocketOptBytes = @import("sa_std/core_util.zig").getSocketOptBytes;
pub const socketIsStream = @import("sa_std/core_util.zig").socketIsStream; pub const socketIsDatagram = @import("sa_std/core_util.zig").socketIsDatagram; pub const getUnixSockAddr = @import("sa_std/core_util.zig").getUnixSockAddr; pub const getResourceLocked = @import("sa_std/core_util.zig").getResourceLocked; pub const registerResourceLocked = @import("sa_std/core_util.zig").registerResourceLocked; pub const registerResource = @import("sa_std/core_util.zig").registerResource; pub const tcpStreamFd = @import("sa_std/core_util.zig").tcpStreamFd; pub const envKeyBytes = @import("sa_std/core_util.zig").envKeyBytes;
pub const envVarsJsonAlloc = @import("sa_std/core_util.zig").envVarsJsonAlloc; pub const envSplitPathsJsonAlloc = @import("sa_std/core_util.zig").envSplitPathsJsonAlloc; pub const envJoinPathsJsonAlloc = @import("sa_std/core_util.zig").envJoinPathsJsonAlloc; pub const sqlite3_prepare = @import("sa_std/core_util.zig").sqlite3_prepare; pub const sqlite3_step = @import("sa_std/core_util.zig").sqlite3_step; pub const sqlite3_finalize = @import("sa_std/core_util.zig").sqlite3_finalize; pub const finishErrnoAny = @import("sa_std/core_util.zig").finishErrnoAny; pub const finishChownErrno = @import("sa_std/core_util.zig").finishChownErrno;
pub const parsePortAscii = @import("sa_std/core_util.zig").parsePortAscii; pub const parseIpv6Ascii = @import("sa_std/core_util.zig").parseIpv6Ascii; pub const parseSocketAddrV6Ascii = @import("sa_std/core_util.zig").parseSocketAddrV6Ascii; pub const tcpConnectTimeoutMs = @import("sa_std/core_util.zig").tcpConnectTimeoutMs;
// --- sa_std/deno.zig ---
pub const sa_deno_cwd = @import("sa_std/deno.zig").sa_deno_cwd; pub const sa_deno_chdir = @import("sa_std/deno.zig").sa_deno_chdir; pub const sa_deno_env_set = @import("sa_std/deno.zig").sa_deno_env_set; pub const sa_deno_env_delete = @import("sa_std/deno.zig").sa_deno_env_delete; pub const sa_deno_random_uuid = @import("sa_std/deno.zig").sa_deno_random_uuid; pub const sa_deno_make_temp_dir = @import("sa_std/deno.zig").sa_deno_make_temp_dir; pub const sa_deno_make_temp_file = @import("sa_std/deno.zig").sa_deno_make_temp_file; pub const sa_deno_args_json = @import("sa_std/deno.zig").sa_deno_args_json;
pub const sa_deno_btoa = @import("sa_std/deno.zig").sa_deno_btoa; pub const sa_deno_atob = @import("sa_std/deno.zig").sa_deno_atob; pub const sa_deno_text_encode = @import("sa_std/deno.zig").sa_deno_text_encode; pub const sa_deno_text_decode = @import("sa_std/deno.zig").sa_deno_text_decode; pub const sa_deno_chat_sse_to_responses = @import("sa_std/deno.zig").sa_deno_chat_sse_to_responses; pub const sa_deno_chat_json_to_responses = @import("sa_std/deno.zig").sa_deno_chat_json_to_responses; pub const sa_deno_responses_sse_normalize = @import("sa_std/deno.zig").sa_deno_responses_sse_normalize; pub const sa_deno_responses_json_normalize = @import("sa_std/deno.zig").sa_deno_responses_json_normalize;
pub const sa_deno_responses_request_normalize = @import("sa_std/deno.zig").sa_deno_responses_request_normalize; pub const sa_deno_responses_chat_fallback_request = @import("sa_std/deno.zig").sa_deno_responses_chat_fallback_request; pub const sa_deno_jsonrpc_params_string_literal = @import("sa_std/deno.zig").sa_deno_jsonrpc_params_string_literal; pub const sa_deno_version_json = @import("sa_std/deno.zig").sa_deno_version_json; pub const sa_deno_version_deno = @import("sa_std/deno.zig").sa_deno_version_deno; pub const sa_deno_build_json = @import("sa_std/deno.zig").sa_deno_build_json; pub const sa_deno_build_os = @import("sa_std/deno.zig").sa_deno_build_os; pub const sa_deno_build_platform_family = @import("sa_std/deno.zig").sa_deno_build_platform_family;
pub const sa_deno_date_now_iso = @import("sa_std/deno.zig").sa_deno_date_now_iso; pub const sa_deno_hostname = @import("sa_std/deno.zig").sa_deno_hostname; pub const sa_deno_os_release = @import("sa_std/deno.zig").sa_deno_os_release; pub const sa_deno_os_uptime = @import("sa_std/deno.zig").sa_deno_os_uptime; pub const sa_deno_loadavg = @import("sa_std/deno.zig").sa_deno_loadavg; pub const sa_deno_system_memory_info = @import("sa_std/deno.zig").sa_deno_system_memory_info; pub const sa_deno_network_interfaces = @import("sa_std/deno.zig").sa_deno_network_interfaces; pub const sa_deno_pid = @import("sa_std/deno.zig").sa_deno_pid;
pub const sa_deno_ppid = @import("sa_std/deno.zig").sa_deno_ppid; pub const sa_deno_uid = @import("sa_std/deno.zig").sa_deno_uid; pub const sa_deno_gid = @import("sa_std/deno.zig").sa_deno_gid; pub const sa_deno_exec_path = @import("sa_std/deno.zig").sa_deno_exec_path; pub const sa_deno_memory_usage = @import("sa_std/deno.zig").sa_deno_memory_usage;
// --- sa_std/dir_stat.zig ---
pub const readDirEntriesLinux = @import("sa_std/dir_stat.zig").readDirEntriesLinux; pub const MetadataHandle = @import("sa_std/dir_stat.zig").MetadataHandle; pub const DirEntrySnapshot = @import("sa_std/dir_stat.zig").DirEntrySnapshot; pub const DirEntriesHandle = @import("sa_std/dir_stat.zig").DirEntriesHandle; pub const statTimeFieldName = @import("sa_std/dir_stat.zig").statTimeFieldName; pub const timeSpecMs = @import("sa_std/dir_stat.zig").timeSpecMs; pub const metadataU64Field = @import("sa_std/dir_stat.zig").metadataU64Field; pub const metadataI64TimeFieldMs = @import("sa_std/dir_stat.zig").metadataI64TimeFieldMs;
pub const metadataI64TimeFieldSec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldSec; pub const metadataI64TimeFieldNsec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldNsec; pub const RawStat = @import("sa_std/dir_stat.zig").RawStat; pub const timestampToRawTs = @import("sa_std/dir_stat.zig").timestampToRawTs; pub const kindModeBits = @import("sa_std/dir_stat.zig").kindModeBits; pub const rawStatFromIo = @import("sa_std/dir_stat.zig").rawStatFromIo; pub const lxStatxNoFollow = @import("sa_std/dir_stat.zig").lxStatxNoFollow; pub const statFromRaw = @import("sa_std/dir_stat.zig").statFromRaw;
pub const statxDevId = @import("sa_std/dir_stat.zig").statxDevId; pub const tsToMs = @import("sa_std/dir_stat.zig").tsToMs; pub const writeJsonBoolField = @import("sa_std/dir_stat.zig").writeJsonBoolField; pub const nsToMs = @import("sa_std/dir_stat.zig").nsToMs; pub const writeJsonIntField = @import("sa_std/dir_stat.zig").writeJsonIntField; pub const writeMetadataJson = @import("sa_std/dir_stat.zig").writeMetadataJson; pub const writeMetadataJsonExt = @import("sa_std/dir_stat.zig").writeMetadataJsonExt; pub const dirEntryKindFromLinuxType = @import("sa_std/dir_stat.zig").dirEntryKindFromLinuxType;
pub const dirEntryKindFromIo = @import("sa_std/dir_stat.zig").dirEntryKindFromIo;
// --- sa_std/dlopen.zig ---
pub const compatibility_dlopen_cookie = @import("sa_std/dlopen.zig").compatibility_dlopen_cookie; pub const compatibility_dl_error = @import("sa_std/dlopen.zig").compatibility_dl_error; pub const DynamicLibHandle = @import("sa_std/dlopen.zig").DynamicLibHandle; pub const dlopen = @import("sa_std/dlopen.zig").dlopen; pub const sa_dl_open = @import("sa_std/dlopen.zig").sa_dl_open; pub const sa_dl_sym = @import("sa_std/dlopen.zig").sa_dl_sym; pub const sa_dl_error = @import("sa_std/dlopen.zig").sa_dl_error;
// --- sa_std/env.zig ---
pub const sa_env_get = @import("sa_std/env.zig").sa_env_get; pub const sa_env_current_dir = @import("sa_std/env.zig").sa_env_current_dir; pub const sa_env_set_current_dir = @import("sa_std/env.zig").sa_env_set_current_dir; pub const sa_env_temp_dir = @import("sa_std/env.zig").sa_env_temp_dir; pub const sa_env_current_exe = @import("sa_std/env.zig").sa_env_current_exe; pub const sa_env_home_dir = @import("sa_std/env.zig").sa_env_home_dir; pub const sa_env_args_json = @import("sa_std/env.zig").sa_env_args_json; pub const sa_env_vars_json = @import("sa_std/env.zig").sa_env_vars_json;
pub const sa_env_split_paths_json = @import("sa_std/env.zig").sa_env_split_paths_json; pub const sa_env_join_paths_json = @import("sa_std/env.zig").sa_env_join_paths_json; pub const sa_env_xdg_data_home_dir = @import("sa_std/env.zig").sa_env_xdg_data_home_dir; pub const sa_env_xdg_config_home_dir = @import("sa_std/env.zig").sa_env_xdg_config_home_dir; pub const sa_env_xdg_state_home_dir = @import("sa_std/env.zig").sa_env_xdg_state_home_dir; pub const sa_env_xdg_cache_home_dir = @import("sa_std/env.zig").sa_env_xdg_cache_home_dir; pub const sa_env_xdg_data_dirs = @import("sa_std/env.zig").sa_env_xdg_data_dirs; pub const sa_env_xdg_config_dirs = @import("sa_std/env.zig").sa_env_xdg_config_dirs;
pub const sa_env_has = @import("sa_std/env.zig").sa_env_has; pub const sa_env_set_var = @import("sa_std/env.zig").sa_env_set_var; pub const sa_env_remove_var = @import("sa_std/env.zig").sa_env_remove_var; pub const sa_env_buffer_data = @import("sa_std/env.zig").sa_env_buffer_data; pub const sa_env_buffer_len = @import("sa_std/env.zig").sa_env_buffer_len; pub const sa_env_buffer_free = @import("sa_std/env.zig").sa_env_buffer_free;
// --- sa_std/fallible.zig ---
pub const statusName = @import("sa_std/fallible.zig").statusName; pub const Fallible = @import("sa_std/fallible.zig").Fallible; pub const ok = @import("sa_std/fallible.zig").ok; pub const fail = @import("sa_std/fallible.zig").fail; pub const netErrorCodeName = @import("sa_std/fallible.zig").netErrorCodeName; pub const sa_std_error_name = @import("sa_std/fallible.zig").sa_std_error_name; pub const sa_std_println = @import("sa_std/fallible.zig").sa_std_println; pub const sa_test_fallible_i32_value = @import("sa_std/fallible.zig").sa_test_fallible_i32_value;
// --- sa_std/fd_core.zig ---
pub const socketFdFromHandle = @import("sa_std/fd_core.zig").socketFdFromHandle; pub const handleToFd = @import("sa_std/fd_core.zig").handleToFd; pub const libcFd = @import("sa_std/fd_core.zig").libcFd; pub const lxAccept = @import("sa_std/fd_core.zig").lxAccept; pub const lxDup = @import("sa_std/fd_core.zig").lxDup; pub const lxIsatty = @import("sa_std/fd_core.zig").lxIsatty; pub const sa_std_fd_as_raw = @import("sa_std/fd_core.zig").sa_std_fd_as_raw; pub const sa_std_fd_dup = @import("sa_std/fd_core.zig").sa_std_fd_dup;
pub const sa_std_fd_dup_raw = @import("sa_std/fd_core.zig").sa_std_fd_dup_raw; pub const sa_std_fd_is_terminal = @import("sa_std/fd_core.zig").sa_std_fd_is_terminal;
// --- sa_std/file_ops.zig ---
pub const filePread = @import("sa_std/file_ops.zig").filePread; pub const filePreadAll = @import("sa_std/file_ops.zig").filePreadAll; pub const filePwrite = @import("sa_std/file_ops.zig").filePwrite; pub const filePwriteAll = @import("sa_std/file_ops.zig").filePwriteAll; pub const fileSeekBy = @import("sa_std/file_ops.zig").fileSeekBy; pub const fileSeekFromEnd = @import("sa_std/file_ops.zig").fileSeekFromEnd; pub const fileGetPos = @import("sa_std/file_ops.zig").fileGetPos; pub const fileSetEndPos = @import("sa_std/file_ops.zig").fileSetEndPos;
pub const writeFormattedInto = @import("sa_std/file_ops.zig").writeFormattedInto; pub const openOwnedBuffer = @import("sa_std/file_ops.zig").openOwnedBuffer; pub const openOwnedByteBuffer = @import("sa_std/file_ops.zig").openOwnedByteBuffer; pub const openOwnedEnvBuffer = @import("sa_std/file_ops.zig").openOwnedEnvBuffer; pub const readProcessOutput = @import("sa_std/file_ops.zig").readProcessOutput; pub const mkdirPathWithMode = @import("sa_std/file_ops.zig").mkdirPathWithMode; pub const mkdirPOne = @import("sa_std/file_ops.zig").mkdirPOne; pub const mkdirP = @import("sa_std/file_ops.zig").mkdirP;
pub const chownId = @import("sa_std/file_ops.zig").chownId; pub const chownPath = @import("sa_std/file_ops.zig").chownPath; pub const writeIpv6SegmentsNative = @import("sa_std/file_ops.zig").writeIpv6SegmentsNative; pub const readIpv6SegmentsNative = @import("sa_std/file_ops.zig").readIpv6SegmentsNative; pub const writeHexLower = @import("sa_std/file_ops.zig").writeHexLower;
// --- sa_std/fmt.zig ---
pub const sa_fmt_i64 = @import("sa_std/fmt.zig").sa_fmt_i64; pub const sa_fmt_i64_into = @import("sa_std/fmt.zig").sa_fmt_i64_into; pub const sa_fmt_u64 = @import("sa_std/fmt.zig").sa_fmt_u64; pub const sa_fmt_u64_into = @import("sa_std/fmt.zig").sa_fmt_u64_into; pub const sa_fmt_f64 = @import("sa_std/fmt.zig").sa_fmt_f64; pub const sa_fmt_f64_into = @import("sa_std/fmt.zig").sa_fmt_f64_into; pub const sa_fmt_bool = @import("sa_std/fmt.zig").sa_fmt_bool; pub const sa_fmt_bool_into = @import("sa_std/fmt.zig").sa_fmt_bool_into;
pub const sa_fmt_bytes = @import("sa_std/fmt.zig").sa_fmt_bytes; pub const sa_fmt_bytes_into = @import("sa_std/fmt.zig").sa_fmt_bytes_into; pub const sa_fmt_buffer_data = @import("sa_std/fmt.zig").sa_fmt_buffer_data; pub const sa_fmt_buffer_len = @import("sa_std/fmt.zig").sa_fmt_buffer_len; pub const sa_fmt_buffer_write_to = @import("sa_std/fmt.zig").sa_fmt_buffer_write_to; pub const sa_fmt_buffer_free = @import("sa_std/fmt.zig").sa_fmt_buffer_free;
// --- sa_std/fs.zig ---
pub const saFsOpenFile = @import("sa_std/fs.zig").saFsOpenFile; pub const sa_fs_open_accmode_mask = @import("sa_std/fs.zig").sa_fs_open_accmode_mask; pub const sa_fs_file_open = @import("sa_std/fs.zig").sa_fs_file_open; pub const sa_fs_file_create = @import("sa_std/fs.zig").sa_fs_file_create; pub const sa_fs_file_close = @import("sa_std/fs.zig").sa_fs_file_close; pub const sa_fs_file_read = @import("sa_std/fs.zig").sa_fs_file_read; pub const sa_fs_file_read_exact = @import("sa_std/fs.zig").sa_fs_file_read_exact; pub const sa_fs_file_write = @import("sa_std/fs.zig").sa_fs_file_write;
pub const sa_fs_file_write_all = @import("sa_std/fs.zig").sa_fs_file_write_all; pub const sa_fs_file_flush = @import("sa_std/fs.zig").sa_fs_file_flush; pub const sa_fs_file_sync_data = @import("sa_std/fs.zig").sa_fs_file_sync_data; pub const sa_fs_file_sync = @import("sa_std/fs.zig").sa_fs_file_sync; pub const sa_fs_file_truncate = @import("sa_std/fs.zig").sa_fs_file_truncate; pub const sa_fs_file_seek = @import("sa_std/fs.zig").sa_fs_file_seek; pub const sa_fs_read_file = @import("sa_std/fs.zig").sa_fs_read_file; pub const sa_fs_read_to_string = @import("sa_std/fs.zig").sa_fs_read_to_string;
pub const sa_fs_write_file = @import("sa_std/fs.zig").sa_fs_write_file; pub const sa_fs_read_buffer_data = @import("sa_std/fs.zig").sa_fs_read_buffer_data; pub const sa_fs_read_buffer_len = @import("sa_std/fs.zig").sa_fs_read_buffer_len; pub const sa_fs_read_buffer_free = @import("sa_std/fs.zig").sa_fs_read_buffer_free; pub const sa_fs_read_file_base64 = @import("sa_std/fs.zig").sa_fs_read_file_base64; pub const sa_fs_write_file_base64 = @import("sa_std/fs.zig").sa_fs_write_file_base64; pub const sa_fs_read_dir_json = @import("sa_std/fs.zig").sa_fs_read_dir_json; pub const sa_fs_dir_buffer_data = @import("sa_std/fs.zig").sa_fs_dir_buffer_data;
pub const sa_fs_dir_buffer_len = @import("sa_std/fs.zig").sa_fs_dir_buffer_len; pub const sa_fs_dir_buffer_free = @import("sa_std/fs.zig").sa_fs_dir_buffer_free; pub const sa_fs_read_dir_entries = @import("sa_std/fs.zig").sa_fs_read_dir_entries; pub const sa_fs_dir_entries_len = @import("sa_std/fs.zig").sa_fs_dir_entries_len; pub const sa_fs_dir_entries_free = @import("sa_std/fs.zig").sa_fs_dir_entries_free; pub const sa_fs_dir_entry_name_ptr = @import("sa_std/fs.zig").sa_fs_dir_entry_name_ptr; pub const sa_fs_dir_entry_name_len = @import("sa_std/fs.zig").sa_fs_dir_entry_name_len; pub const sa_fs_dir_entry_file_name_ptr = @import("sa_std/fs.zig").sa_fs_dir_entry_file_name_ptr;
pub const sa_fs_dir_entry_file_name_len = @import("sa_std/fs.zig").sa_fs_dir_entry_file_name_len; pub const sa_fs_dir_entry_kind = @import("sa_std/fs.zig").sa_fs_dir_entry_kind; pub const sa_fs_dir_entry_ino = @import("sa_std/fs.zig").sa_fs_dir_entry_ino; pub const sa_fs_dir_entry_free = @import("sa_std/fs.zig").sa_fs_dir_entry_free; pub const sa_fs_metadata = @import("sa_std/fs.zig").sa_fs_metadata; pub const sa_fs_metadata_json = @import("sa_std/fs.zig").sa_fs_metadata_json; pub const sa_fs_metadata_is_file = @import("sa_std/fs.zig").sa_fs_metadata_is_file; pub const sa_fs_metadata_is_directory = @import("sa_std/fs.zig").sa_fs_metadata_is_directory;
pub const sa_fs_metadata_is_symlink = @import("sa_std/fs.zig").sa_fs_metadata_is_symlink; pub const sa_fs_metadata_is_block_device = @import("sa_std/fs.zig").sa_fs_metadata_is_block_device; pub const sa_fs_metadata_is_char_device = @import("sa_std/fs.zig").sa_fs_metadata_is_char_device; pub const sa_fs_metadata_is_fifo = @import("sa_std/fs.zig").sa_fs_metadata_is_fifo; pub const sa_fs_metadata_is_socket = @import("sa_std/fs.zig").sa_fs_metadata_is_socket; pub const sa_fs_metadata_modified_ms = @import("sa_std/fs.zig").sa_fs_metadata_modified_ms; pub const sa_fs_metadata_created_ms = @import("sa_std/fs.zig").sa_fs_metadata_created_ms; pub const sa_fs_metadata_accessed_ms = @import("sa_std/fs.zig").sa_fs_metadata_accessed_ms;
pub const sa_fs_metadata_changed_ms = @import("sa_std/fs.zig").sa_fs_metadata_changed_ms; pub const sa_fs_metadata_len = @import("sa_std/fs.zig").sa_fs_metadata_len; pub const sa_fs_metadata_mode = @import("sa_std/fs.zig").sa_fs_metadata_mode; pub const sa_fs_metadata_uid = @import("sa_std/fs.zig").sa_fs_metadata_uid; pub const sa_fs_metadata_gid = @import("sa_std/fs.zig").sa_fs_metadata_gid; pub const sa_fs_metadata_ino = @import("sa_std/fs.zig").sa_fs_metadata_ino; pub const sa_fs_metadata_dev = @import("sa_std/fs.zig").sa_fs_metadata_dev; pub const sa_fs_metadata_nlink = @import("sa_std/fs.zig").sa_fs_metadata_nlink;
pub const sa_fs_metadata_rdev = @import("sa_std/fs.zig").sa_fs_metadata_rdev; pub const sa_fs_metadata_blksize = @import("sa_std/fs.zig").sa_fs_metadata_blksize; pub const sa_fs_metadata_blocks = @import("sa_std/fs.zig").sa_fs_metadata_blocks; pub const sa_fs_metadata_st_dev = @import("sa_std/fs.zig").sa_fs_metadata_st_dev; pub const sa_fs_metadata_st_ino = @import("sa_std/fs.zig").sa_fs_metadata_st_ino; pub const sa_fs_metadata_st_mode = @import("sa_std/fs.zig").sa_fs_metadata_st_mode; pub const sa_fs_metadata_st_nlink = @import("sa_std/fs.zig").sa_fs_metadata_st_nlink; pub const sa_fs_metadata_st_uid = @import("sa_std/fs.zig").sa_fs_metadata_st_uid;
pub const sa_fs_metadata_st_gid = @import("sa_std/fs.zig").sa_fs_metadata_st_gid; pub const sa_fs_metadata_st_rdev = @import("sa_std/fs.zig").sa_fs_metadata_st_rdev; pub const sa_fs_metadata_st_size = @import("sa_std/fs.zig").sa_fs_metadata_st_size; pub const sa_fs_metadata_st_atime = @import("sa_std/fs.zig").sa_fs_metadata_st_atime; pub const sa_fs_metadata_st_atime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_atime_nsec; pub const sa_fs_metadata_st_mtime = @import("sa_std/fs.zig").sa_fs_metadata_st_mtime; pub const sa_fs_metadata_st_mtime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_mtime_nsec; pub const sa_fs_metadata_st_ctime = @import("sa_std/fs.zig").sa_fs_metadata_st_ctime;
pub const sa_fs_metadata_st_ctime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_ctime_nsec; pub const sa_fs_metadata_st_blksize = @import("sa_std/fs.zig").sa_fs_metadata_st_blksize; pub const sa_fs_metadata_st_blocks = @import("sa_std/fs.zig").sa_fs_metadata_st_blocks; pub const sa_fs_metadata_free = @import("sa_std/fs.zig").sa_fs_metadata_free; pub const sa_fs_remove_file = @import("sa_std/fs.zig").sa_fs_remove_file; pub const sa_fs_rename = @import("sa_std/fs.zig").sa_fs_rename; pub const sa_fs_make_dir = @import("sa_std/fs.zig").sa_fs_make_dir; pub const sa_fs_make_dir_mode = @import("sa_std/fs.zig").sa_fs_make_dir_mode;
pub const sa_fs_mkdir_p = @import("sa_std/fs.zig").sa_fs_mkdir_p; pub const sa_fs_create_dir = @import("sa_std/fs.zig").sa_fs_create_dir; pub const sa_fs_create_dir_mode = @import("sa_std/fs.zig").sa_fs_create_dir_mode; pub const sa_fs_remove_dir = @import("sa_std/fs.zig").sa_fs_remove_dir; pub const sa_fs_remove_dir_all = @import("sa_std/fs.zig").sa_fs_remove_dir_all; pub const sa_fs_remove_path = @import("sa_std/fs.zig").sa_fs_remove_path; pub const sa_fs_copy_file = @import("sa_std/fs.zig").sa_fs_copy_file; pub const sa_fs_set_permissions = @import("sa_std/fs.zig").sa_fs_set_permissions;
pub const sa_fs_set_times_ms = @import("sa_std/fs.zig").sa_fs_set_times_ms; pub const sa_fs_hard_link = @import("sa_std/fs.zig").sa_fs_hard_link; pub const sa_fs_symlink = @import("sa_std/fs.zig").sa_fs_symlink; pub const sa_fs_chown = @import("sa_std/fs.zig").sa_fs_chown; pub const sa_fs_lchown = @import("sa_std/fs.zig").sa_fs_lchown; pub const sa_fs_fchown = @import("sa_std/fs.zig").sa_fs_fchown; pub const sa_fs_chroot = @import("sa_std/fs.zig").sa_fs_chroot; pub const sa_fs_mkfifo = @import("sa_std/fs.zig").sa_fs_mkfifo;
// --- sa_std/handles.zig ---
pub const BufferHandle = @import("sa_std/handles.zig").BufferHandle; pub const DirEntryHandle = @import("sa_std/handles.zig").DirEntryHandle; pub const NetAddrHandle = @import("sa_std/handles.zig").NetAddrHandle; pub const NetAddrListHandle = @import("sa_std/handles.zig").NetAddrListHandle; pub const FmtHandle = @import("sa_std/handles.zig").FmtHandle; pub const JsonBufferHandle = @import("sa_std/handles.zig").JsonBufferHandle; pub const JsonWriterHandle = @import("sa_std/handles.zig").JsonWriterHandle; pub const EnvHandle = @import("sa_std/handles.zig").EnvHandle;
pub const TimeDate = @import("sa_std/handles.zig").TimeDate; pub const Timeval = @import("sa_std/handles.zig").Timeval; pub const LingerOption = @import("sa_std/handles.zig").LingerOption; pub const Timespec = @import("sa_std/handles.zig").Timespec; pub const OwnedFdHandle = @import("sa_std/handles.zig").OwnedFdHandle; pub const TerminalSession = @import("sa_std/handles.zig").TerminalSession; pub const TcpListener = @import("sa_std/handles.zig").TcpListener; pub const Resource = @import("sa_std/handles.zig").Resource;
// --- sa_std/hub.zig ---
pub const policyAllows = @import("sa_std/hub.zig").policyAllows; pub const is_wasm = @import("sa_std/hub.zig").is_wasm; pub const is_linux = @import("sa_std/hub.zig").is_linux; pub const fbsd_sys_nmln = @import("sa_std/hub.zig").fbsd_sys_nmln; pub const SA_PLUGIN_DESCRIPTOR_SYMBOL = @import("sa_std/hub.zig").SA_PLUGIN_DESCRIPTOR_SYMBOL; pub const DEFAULT_CAPTURE_LIMIT = @import("sa_std/hub.zig").DEFAULT_CAPTURE_LIMIT; pub const empty_bytes = @import("sa_std/hub.zig").empty_bytes; pub const empty_mut_bytes = @import("sa_std/hub.zig").empty_mut_bytes;
pub const addressHostText = @import("sa_std/hub.zig").addressHostText; pub const lenAsUsize = @import("sa_std/hub.zig").lenAsUsize; pub const constBytes = @import("sa_std/hub.zig").constBytes; pub const errnoToAny = @import("sa_std/hub.zig").errnoToAny; pub const libc = @import("sa_std/hub.zig").libc; pub const icu_err_overflow = @import("sa_std/hub.zig").icu_err_overflow; pub const monthNames = @import("sa_std/hub.zig").monthNames;
// --- sa_std/iface_json.zig ---
pub const struct_sockaddr = @import("sa_std/iface_json.zig").struct_sockaddr; pub const struct_ifaddrs = @import("sa_std/iface_json.zig").struct_ifaddrs; pub const appendJsonEscapedString = @import("sa_std/iface_json.zig").appendJsonEscapedString; pub const buildInterfaceAddressesJson = @import("sa_std/iface_json.zig").buildInterfaceAddressesJson;
// --- sa_std/io.zig ---
pub const sa_io_read_line = @import("sa_std/io.zig").sa_io_read_line; pub const sa_io_stdin = @import("sa_std/io.zig").sa_io_stdin; pub const sa_io_stdout = @import("sa_std/io.zig").sa_io_stdout; pub const sa_io_stderr = @import("sa_std/io.zig").sa_io_stderr; pub const sa_io_read = @import("sa_std/io.zig").sa_io_read; pub const sa_io_read_exact = @import("sa_std/io.zig").sa_io_read_exact; pub const sa_io_write = @import("sa_std/io.zig").sa_io_write; pub const sa_io_write_all = @import("sa_std/io.zig").sa_io_write_all;
pub const sa_io_flush = @import("sa_std/io.zig").sa_io_flush; pub const sa_io_close = @import("sa_std/io.zig").sa_io_close; pub const sa_io_buffer_data = @import("sa_std/io.zig").sa_io_buffer_data; pub const sa_io_buffer_len = @import("sa_std/io.zig").sa_io_buffer_len; pub const sa_io_buffer_free = @import("sa_std/io.zig").sa_io_buffer_free;
// --- sa_std/io_plan.zig ---
pub const readHandleLocked = @import("sa_std/io_plan.zig").readHandleLocked; pub const IoPlan = @import("sa_std/io_plan.zig").IoPlan; pub const ioPlanLocked = @import("sa_std/io_plan.zig").ioPlanLocked; pub const readHandle = @import("sa_std/io_plan.zig").readHandle; pub const writeHandle = @import("sa_std/io_plan.zig").writeHandle; pub const lxRead = @import("sa_std/io_plan.zig").lxRead; pub const sa_std_write = @import("sa_std/io_plan.zig").sa_std_write; pub const sa_std_read = @import("sa_std/io_plan.zig").sa_std_read;
// --- sa_std/ip_parse.zig ---
pub const hostBytes = @import("sa_std/ip_parse.zig").hostBytes; pub const portFromU32 = @import("sa_std/ip_parse.zig").portFromU32; pub const parseIp4Address = @import("sa_std/ip_parse.zig").parseIp4Address; pub const parseV6HalfFreebsd = @import("sa_std/ip_parse.zig").parseV6HalfFreebsd; pub const parseIpv6NumericFreebsd = @import("sa_std/ip_parse.zig").parseIpv6NumericFreebsd; pub const parseIp6FreebsdParts = @import("sa_std/ip_parse.zig").parseIp6FreebsdParts; pub const parseIp6Address = @import("sa_std/ip_parse.zig").parseIp6Address; pub const resolveFirstAddressFromParts = @import("sa_std/ip_parse.zig").resolveFirstAddressFromParts;
pub const resolveFirstSocketAddress = @import("sa_std/ip_parse.zig").resolveFirstSocketAddress; pub const parseIpv4Ascii = @import("sa_std/ip_parse.zig").parseIpv4Ascii;
// --- sa_std/json.zig ---
pub const sa_json_parse = @import("sa_std/json.zig").sa_json_parse; pub const sa_json_kind = @import("sa_std/json.zig").sa_json_kind; pub const sa_json_object_get = @import("sa_std/json.zig").sa_json_object_get; pub const sa_json_array_get = @import("sa_std/json.zig").sa_json_array_get; pub const sa_json_object_key_at = @import("sa_std/json.zig").sa_json_object_key_at; pub const sa_json_object_get_string = @import("sa_std/json.zig").sa_json_object_get_string; pub const sa_json_object_get_bool = @import("sa_std/json.zig").sa_json_object_get_bool; pub const sa_json_object_get_i64 = @import("sa_std/json.zig").sa_json_object_get_i64;
pub const sa_json_object_get_f64 = @import("sa_std/json.zig").sa_json_object_get_f64; pub const sa_json_as_f64 = @import("sa_std/json.zig").sa_json_as_f64; pub const sa_json_as_i64 = @import("sa_std/json.zig").sa_json_as_i64; pub const sa_json_as_bool = @import("sa_std/json.zig").sa_json_as_bool; pub const sa_json_string_ptr = @import("sa_std/json.zig").sa_json_string_ptr; pub const sa_json_string_len = @import("sa_std/json.zig").sa_json_string_len; pub const sa_json_value_count = @import("sa_std/json.zig").sa_json_value_count; pub const sa_json_free = @import("sa_std/json.zig").sa_json_free;
pub const sa_json_stringify = @import("sa_std/json.zig").sa_json_stringify; pub const sa_json_object_set_string = @import("sa_std/json.zig").sa_json_object_set_string; pub const sa_json_object_set_i64 = @import("sa_std/json.zig").sa_json_object_set_i64; pub const sa_json_object_set_f64 = @import("sa_std/json.zig").sa_json_object_set_f64; pub const sa_json_object_set_bool = @import("sa_std/json.zig").sa_json_object_set_bool; pub const sa_json_object_set_null = @import("sa_std/json.zig").sa_json_object_set_null; pub const sa_json_object_set_node = @import("sa_std/json.zig").sa_json_object_set_node; pub const sa_json_object_remove = @import("sa_std/json.zig").sa_json_object_remove;
pub const sa_json_array_push_string = @import("sa_std/json.zig").sa_json_array_push_string; pub const sa_json_array_push_i64 = @import("sa_std/json.zig").sa_json_array_push_i64; pub const sa_json_array_push_f64 = @import("sa_std/json.zig").sa_json_array_push_f64; pub const sa_json_array_push_bool = @import("sa_std/json.zig").sa_json_array_push_bool; pub const sa_json_array_push_null = @import("sa_std/json.zig").sa_json_array_push_null; pub const sa_json_array_push_node = @import("sa_std/json.zig").sa_json_array_push_node; pub const sa_json_scanner_new = @import("sa_std/json.zig").sa_json_scanner_new; pub const sa_json_scanner_feed = @import("sa_std/json.zig").sa_json_scanner_feed;
pub const sa_json_scanner_end_input = @import("sa_std/json.zig").sa_json_scanner_end_input; pub const sa_json_scanner_next = @import("sa_std/json.zig").sa_json_scanner_next; pub const sa_json_scanner_free = @import("sa_std/json.zig").sa_json_scanner_free; pub const sa_json_stream_new = @import("sa_std/json.zig").sa_json_stream_new; pub const sa_json_stream_next = @import("sa_std/json.zig").sa_json_stream_next; pub const sa_json_stream_get_slice_ptr = @import("sa_std/json.zig").sa_json_stream_get_slice_ptr; pub const sa_json_stream_get_slice_len = @import("sa_std/json.zig").sa_json_stream_get_slice_len; pub const sa_json_stream_free = @import("sa_std/json.zig").sa_json_stream_free;
pub const sa_json_writer_free = @import("sa_std/json.zig").sa_json_writer_free; pub const sa_json_writer_new = @import("sa_std/json.zig").sa_json_writer_new; pub const sa_json_writer_begin_object = @import("sa_std/json.zig").sa_json_writer_begin_object; pub const sa_json_writer_end_object = @import("sa_std/json.zig").sa_json_writer_end_object; pub const sa_json_writer_begin_array = @import("sa_std/json.zig").sa_json_writer_begin_array; pub const sa_json_writer_end_array = @import("sa_std/json.zig").sa_json_writer_end_array; pub const sa_json_writer_object_field = @import("sa_std/json.zig").sa_json_writer_object_field; pub const sa_json_writer_field_string = @import("sa_std/json.zig").sa_json_writer_field_string;
pub const sa_json_writer_field_bool = @import("sa_std/json.zig").sa_json_writer_field_bool; pub const sa_json_writer_field_i64 = @import("sa_std/json.zig").sa_json_writer_field_i64; pub const sa_json_writer_field_f64 = @import("sa_std/json.zig").sa_json_writer_field_f64; pub const sa_json_writer_field_null = @import("sa_std/json.zig").sa_json_writer_field_null; pub const sa_json_writer_field_node = @import("sa_std/json.zig").sa_json_writer_field_node; pub const sa_json_writer_write_bool = @import("sa_std/json.zig").sa_json_writer_write_bool; pub const sa_json_writer_write_i64 = @import("sa_std/json.zig").sa_json_writer_write_i64; pub const sa_json_writer_write_f64 = @import("sa_std/json.zig").sa_json_writer_write_f64;
pub const sa_json_writer_write_string = @import("sa_std/json.zig").sa_json_writer_write_string; pub const sa_json_writer_write_null = @import("sa_std/json.zig").sa_json_writer_write_null; pub const sa_json_writer_write_node = @import("sa_std/json.zig").sa_json_writer_write_node; pub const sa_json_writer_finish = @import("sa_std/json.zig").sa_json_writer_finish; pub const sa_json_writer_finish_buffer = @import("sa_std/json.zig").sa_json_writer_finish_buffer; pub const sa_json_buffer_data = @import("sa_std/json.zig").sa_json_buffer_data; pub const sa_json_buffer_len = @import("sa_std/json.zig").sa_json_buffer_len; pub const sa_json_buffer_free = @import("sa_std/json.zig").sa_json_buffer_free;
// --- sa_std/json_node.zig ---
pub const JsonDocumentHandle = @import("sa_std/json_node.zig").JsonDocumentHandle; pub const JsonPathSegment = @import("sa_std/json_node.zig").JsonPathSegment; pub const freeJsonPath = @import("sa_std/json_node.zig").freeJsonPath; pub const jsonPathAppend = @import("sa_std/json_node.zig").jsonPathAppend; pub const JsonNodeHandle = @import("sa_std/json_node.zig").JsonNodeHandle; pub const registerJsonNode = @import("sa_std/json_node.zig").registerJsonNode; pub const acquireJsonNode = @import("sa_std/json_node.zig").acquireJsonNode; pub const jsonResolvePathPtr = @import("sa_std/json_node.zig").jsonResolvePathPtr;
pub const jsonResolvePath = @import("sa_std/json_node.zig").jsonResolvePath; pub const jsonDocumentFromSlice = @import("sa_std/json_node.zig").jsonDocumentFromSlice; pub const jsonObjectGet = @import("sa_std/json_node.zig").jsonObjectGet; pub const jsonArrayGet = @import("sa_std/json_node.zig").jsonArrayGet; pub const jsonObjectKeyAt = @import("sa_std/json_node.zig").jsonObjectKeyAt; pub const JsonMutation = @import("sa_std/json_node.zig").JsonMutation; pub const jsonMutationTarget = @import("sa_std/json_node.zig").jsonMutationTarget; pub const jsonObjectSetLocked = @import("sa_std/json_node.zig").jsonObjectSetLocked;
pub const jsonArrayPushLocked = @import("sa_std/json_node.zig").jsonArrayPushLocked; pub const jsonObjectRemoveLocked = @import("sa_std/json_node.zig").jsonObjectRemoveLocked;
// --- sa_std/json_scan.zig ---
pub const JsonScannerHandle = @import("sa_std/json_scan.zig").JsonScannerHandle; pub const JsonStreamHandle = @import("sa_std/json_scan.zig").JsonStreamHandle; pub const tokenTextBytes = @import("sa_std/json_scan.zig").tokenTextBytes; pub const jsonScannerFeed = @import("sa_std/json_scan.zig").jsonScannerFeed;
// --- sa_std/json_util.zig ---
pub const jsonTextSlice = @import("sa_std/json_util.zig").jsonTextSlice; pub const jsonStringifyAlloc = @import("sa_std/json_util.zig").jsonStringifyAlloc; pub const jsonSerializeBuffer = @import("sa_std/json_util.zig").jsonSerializeBuffer; pub const ListWriter = @import("sa_std/json_util.zig").ListWriter; pub const listWriter = @import("sa_std/json_util.zig").listWriter; pub const stringifyToList = @import("sa_std/json_util.zig").stringifyToList; pub const appendJsonString = @import("sa_std/json_util.zig").appendJsonString; pub const jsonStringLiteralAlloc = @import("sa_std/json_util.zig").jsonStringLiteralAlloc;
pub const jsonRpcParamLookupKey = @import("sa_std/json_util.zig").jsonRpcParamLookupKey; pub const jsonRpcParamsStringLiteralAlloc = @import("sa_std/json_util.zig").jsonRpcParamsStringLiteralAlloc; pub const jsonObjectGetValue = @import("sa_std/json_util.zig").jsonObjectGetValue;
// --- sa_std/lx.zig ---
pub const lxCheck = @import("sa_std/lx.zig").lxCheck; pub const lxClose = @import("sa_std/lx.zig").lxClose; pub const lxWrite = @import("sa_std/lx.zig").lxWrite; pub const lxReadv = @import("sa_std/lx.zig").lxReadv; pub const lxWritev = @import("sa_std/lx.zig").lxWritev; pub const lxSocket = @import("sa_std/lx.zig").lxSocket; pub const lxShutdown = @import("sa_std/lx.zig").lxShutdown; pub const lxSend = @import("sa_std/lx.zig").lxSend;
pub const lxRecv = @import("sa_std/lx.zig").lxRecv; pub const lxSendto = @import("sa_std/lx.zig").lxSendto; pub const lxRecvfrom = @import("sa_std/lx.zig").lxRecvfrom; pub const lxUnlink = @import("sa_std/lx.zig").lxUnlink; pub const lxMkdirat = @import("sa_std/lx.zig").lxMkdirat; pub const lxFchmodat = @import("sa_std/lx.zig").lxFchmodat; pub const lxLink = @import("sa_std/lx.zig").lxLink; pub const lxFutimens = @import("sa_std/lx.zig").lxFutimens;
pub const lxKill = @import("sa_std/lx.zig").lxKill; pub const lxGetpeername = @import("sa_std/lx.zig").lxGetpeername; pub const lxEpollCreate1 = @import("sa_std/lx.zig").lxEpollCreate1; pub const lxEpollCtl = @import("sa_std/lx.zig").lxEpollCtl; pub const lxEpollWait = @import("sa_std/lx.zig").lxEpollWait; pub const lxSendfile = @import("sa_std/lx.zig").lxSendfile;
// --- sa_std/math.zig ---
pub const sa_math_floor = @import("sa_std/math.zig").sa_math_floor; pub const sa_math_ceil = @import("sa_std/math.zig").sa_math_ceil; pub const sa_math_sqrt = @import("sa_std/math.zig").sa_math_sqrt; pub const sa_math_sin = @import("sa_std/math.zig").sa_math_sin; pub const sa_math_cos = @import("sa_std/math.zig").sa_math_cos; pub const sa_math_pow = @import("sa_std/math.zig").sa_math_pow; pub const sa_math_random = @import("sa_std/math.zig").sa_math_random;
// --- sa_std/net.zig ---
pub const sa_net_iov = @import("sa_std/net.zig").sa_net_iov; pub const sa_net_tcp_connect = @import("sa_std/net.zig").sa_net_tcp_connect; pub const sa_net_tcp_stream_read = @import("sa_std/net.zig").sa_net_tcp_stream_read; pub const sa_net_tcp_stream_peek = @import("sa_std/net.zig").sa_net_tcp_stream_peek; pub const sa_net_tcp_stream_write = @import("sa_std/net.zig").sa_net_tcp_stream_write; pub const sa_net_tcp_stream_write_all = @import("sa_std/net.zig").sa_net_tcp_stream_write_all; pub const sa_net_tcp_stream_read_exact = @import("sa_std/net.zig").sa_net_tcp_stream_read_exact; pub const sa_net_tcp_stream_flush = @import("sa_std/net.zig").sa_net_tcp_stream_flush;
pub const sa_net_tcp_stream_peer_addr = @import("sa_std/net.zig").sa_net_tcp_stream_peer_addr; pub const sa_net_tcp_stream_shutdown = @import("sa_std/net.zig").sa_net_tcp_stream_shutdown; pub const sa_net_tcp_stream_set_read_timeout = @import("sa_std/net.zig").sa_net_tcp_stream_set_read_timeout; pub const sa_net_tcp_stream_set_write_timeout = @import("sa_std/net.zig").sa_net_tcp_stream_set_write_timeout; pub const sa_net_tcp_stream_set_nonblocking = @import("sa_std/net.zig").sa_net_tcp_stream_set_nonblocking; pub const sa_net_tcp_stream_set_nodelay = @import("sa_std/net.zig").sa_net_tcp_stream_set_nodelay; pub const sa_net_tcp_stream_set_ttl = @import("sa_std/net.zig").sa_net_tcp_stream_set_ttl; pub const sa_net_tcp_stream_close = @import("sa_std/net.zig").sa_net_tcp_stream_close;
pub const sa_net_tcp_listener_bind = @import("sa_std/net.zig").sa_net_tcp_listener_bind; pub const sa_net_tcp_listener_accept = @import("sa_std/net.zig").sa_net_tcp_listener_accept; pub const sa_net_tcp_listener_local_addr = @import("sa_std/net.zig").sa_net_tcp_listener_local_addr; pub const sa_net_tcp_listener_close = @import("sa_std/net.zig").sa_net_tcp_listener_close; pub const sa_net_udp_set_read_timeout = @import("sa_std/net.zig").sa_net_udp_set_read_timeout; pub const sa_net_udp_set_write_timeout = @import("sa_std/net.zig").sa_net_udp_set_write_timeout; pub const sa_net_udp_set_nonblocking = @import("sa_std/net.zig").sa_net_udp_set_nonblocking; pub const sa_net_udp_set_broadcast = @import("sa_std/net.zig").sa_net_udp_set_broadcast;
pub const sa_net_udp_set_ttl = @import("sa_std/net.zig").sa_net_udp_set_ttl; pub const sa_net_udp_set_multicast_loop_v4 = @import("sa_std/net.zig").sa_net_udp_set_multicast_loop_v4; pub const sa_net_udp_set_multicast_ttl_v4 = @import("sa_std/net.zig").sa_net_udp_set_multicast_ttl_v4; pub const sa_net_udp_join_multicast_v4 = @import("sa_std/net.zig").sa_net_udp_join_multicast_v4; pub const sa_net_udp_leave_multicast_v4 = @import("sa_std/net.zig").sa_net_udp_leave_multicast_v4; pub const sa_net_udp_join_multicast_v6 = @import("sa_std/net.zig").sa_net_udp_join_multicast_v6; pub const sa_net_udp_leave_multicast_v6 = @import("sa_std/net.zig").sa_net_udp_leave_multicast_v6; pub const sa_net_udp_bind = @import("sa_std/net.zig").sa_net_udp_bind;
pub const sa_net_udp_connect = @import("sa_std/net.zig").sa_net_udp_connect; pub const sa_net_udp_local_addr = @import("sa_std/net.zig").sa_net_udp_local_addr; pub const sa_net_udp_send = @import("sa_std/net.zig").sa_net_udp_send; pub const sa_net_udp_recv = @import("sa_std/net.zig").sa_net_udp_recv; pub const sa_net_udp_peek = @import("sa_std/net.zig").sa_net_udp_peek; pub const sa_net_udp_send_to = @import("sa_std/net.zig").sa_net_udp_send_to; pub const sa_net_udp_recv_from = @import("sa_std/net.zig").sa_net_udp_recv_from; pub const sa_net_udp_peek_from = @import("sa_std/net.zig").sa_net_udp_peek_from;
pub const sa_net_udp_close = @import("sa_std/net.zig").sa_net_udp_close; pub const sa_net_addr_host = @import("sa_std/net.zig").sa_net_addr_host; pub const sa_net_addr_host_len = @import("sa_std/net.zig").sa_net_addr_host_len; pub const sa_net_addr_port = @import("sa_std/net.zig").sa_net_addr_port; pub const sa_net_addr_family = @import("sa_std/net.zig").sa_net_addr_family; pub const sa_net_addr_scope_id = @import("sa_std/net.zig").sa_net_addr_scope_id; pub const sa_net_addr_free = @import("sa_std/net.zig").sa_net_addr_free; pub const sa_net_ipv4_parse_ascii = @import("sa_std/net.zig").sa_net_ipv4_parse_ascii;
pub const sa_net_socket_addr_v4_parse_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v4_parse_ascii; pub const sa_net_ipv6_parse_ascii = @import("sa_std/net.zig").sa_net_ipv6_parse_ascii; pub const sa_net_socket_addr_v6_parse_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v6_parse_ascii; pub const sa_net_ipv4_format_ascii = @import("sa_std/net.zig").sa_net_ipv4_format_ascii; pub const sa_net_ipv6_format_ascii = @import("sa_std/net.zig").sa_net_ipv6_format_ascii; pub const sa_net_socket_addr_v4_format_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v4_format_ascii; pub const sa_net_socket_addr_v6_format_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v6_format_ascii; pub const sa_net_unix_addr_kind = @import("sa_std/net.zig").sa_net_unix_addr_kind;
pub const sa_net_unix_addr_is_unnamed = @import("sa_std/net.zig").sa_net_unix_addr_is_unnamed; pub const sa_net_unix_addr_path_ptr = @import("sa_std/net.zig").sa_net_unix_addr_path_ptr; pub const sa_net_unix_addr_path_len = @import("sa_std/net.zig").sa_net_unix_addr_path_len; pub const sa_net_unix_addr_abstract_ptr = @import("sa_std/net.zig").sa_net_unix_addr_abstract_ptr; pub const sa_net_unix_addr_abstract_len = @import("sa_std/net.zig").sa_net_unix_addr_abstract_len; pub const sa_net_unix_addr_free = @import("sa_std/net.zig").sa_net_unix_addr_free;
// --- sa_std/normalize.zig ---
pub const normalizeMcpServerNameAlloc = @import("sa_std/normalize.zig").normalizeMcpServerNameAlloc; pub const normalizeResponsesRequestArgumentsString = @import("sa_std/normalize.zig").normalizeResponsesRequestArgumentsString; pub const normalizeResponsesRequestValue = @import("sa_std/normalize.zig").normalizeResponsesRequestValue; pub const denoResponsesRequestNormalize = @import("sa_std/normalize.zig").denoResponsesRequestNormalize;
// --- sa_std/policy.zig ---
pub const policyBootstrap = @import("sa_std/policy.zig").policyBootstrap; pub const policyBootstrapWriteStderr = @import("sa_std/policy.zig").policyBootstrapWriteStderr; pub const policyAuditSink = @import("sa_std/policy.zig").policyAuditSink; pub const policyBootstrapFail = @import("sa_std/policy.zig").policyBootstrapFail; pub const policyEnvFlag = @import("sa_std/policy.zig").policyEnvFlag; pub const installPolicyText = @import("sa_std/policy.zig").installPolicyText; pub const applySigpipeIgnore = @import("sa_std/policy.zig").applySigpipeIgnore; pub const installSigpipeIgnore = @import("sa_std/policy.zig").installSigpipeIgnore;
pub const sa_install_sigpipe_ignore = @import("sa_std/policy.zig").sa_install_sigpipe_ignore;
// --- sa_std/proc_wait.zig ---
pub const WasiW = @import("sa_std/proc_wait.zig").WasiW; pub const WT = @import("sa_std/proc_wait.zig").WT; pub const w_exited = @import("sa_std/proc_wait.zig").w_exited; pub const w_nohang = @import("sa_std/proc_wait.zig").w_nohang; pub const ProcessHandle = @import("sa_std/proc_wait.zig").ProcessHandle; pub const capture_fd_to_owned = @import("sa_std/proc_wait.zig").capture_fd_to_owned; pub const statusFromWaitStatus = @import("sa_std/proc_wait.zig").statusFromWaitStatus; pub const rawWaitStatus = @import("sa_std/proc_wait.zig").rawWaitStatus;
pub const waitStatusCode = @import("sa_std/proc_wait.zig").waitStatusCode; pub const waitStatusSignal = @import("sa_std/proc_wait.zig").waitStatusSignal; pub const waitStatusCoreDumped = @import("sa_std/proc_wait.zig").waitStatusCoreDumped; pub const waitStatusStoppedSignal = @import("sa_std/proc_wait.zig").waitStatusStoppedSignal; pub const waitStatusContinued = @import("sa_std/proc_wait.zig").waitStatusContinued; pub const waitProcessIgnoringMissing = @import("sa_std/proc_wait.zig").waitProcessIgnoringMissing; pub const waitPidfdStatus = @import("sa_std/proc_wait.zig").waitPidfdStatus; pub const finalizeProcessExit = @import("sa_std/proc_wait.zig").finalizeProcessExit;
pub const sa_std_pidfd_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait_raw; pub const sa_std_pidfd_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait; pub const sa_std_pidfd_try_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait_raw; pub const sa_std_pidfd_try_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait;
// --- sa_std/pthread.zig ---
pub const pthread_drop = @import("sa_std/pthread.zig").pthread_drop; pub const PthreadEntryFn = @import("sa_std/pthread.zig").PthreadEntryFn; pub const PthreadTask = @import("sa_std/pthread.zig").PthreadTask; pub const PthreadHandle = @import("sa_std/pthread.zig").PthreadHandle; pub const RawPthreadOwner = @import("sa_std/pthread.zig").RawPthreadOwner; pub const RawPthreadTransfer = @import("sa_std/pthread.zig").RawPthreadTransfer; pub const pthreadToRaw = @import("sa_std/pthread.zig").pthreadToRaw; pub const rawToPthread = @import("sa_std/pthread.zig").rawToPthread;
pub const pthreadTaskMain = @import("sa_std/pthread.zig").pthreadTaskMain; pub const pthreadTaskMainC = @import("sa_std/pthread.zig").pthreadTaskMainC; pub const mapPthreadCreateError = @import("sa_std/pthread.zig").mapPthreadCreateError; pub const spawnPthread = @import("sa_std/pthread.zig").spawnPthread; pub const joinPthreadHandle = @import("sa_std/pthread.zig").joinPthreadHandle; pub const allocPthreadHandle = @import("sa_std/pthread.zig").allocPthreadHandle; pub const takePthreadHandle = @import("sa_std/pthread.zig").takePthreadHandle; pub const freePthreadHandle = @import("sa_std/pthread.zig").freePthreadHandle;
pub const transferPthreadHandleToRaw = @import("sa_std/pthread.zig").transferPthreadHandleToRaw; pub const findRawPthreadTask = @import("sa_std/pthread.zig").findRawPthreadTask; pub const removeRawPthreadOwner = @import("sa_std/pthread.zig").removeRawPthreadOwner; pub const pthread_spawn = @import("sa_std/pthread.zig").pthread_spawn; pub const pthread_spawn_detached = @import("sa_std/pthread.zig").pthread_spawn_detached; pub const pthread_join = @import("sa_std/pthread.zig").pthread_join; pub const sa_thread_as_pthread_t = @import("sa_std/pthread.zig").sa_thread_as_pthread_t; pub const sa_thread_into_pthread_t = @import("sa_std/pthread.zig").sa_thread_into_pthread_t;
pub const sa_thread_raw_pthread_join = @import("sa_std/pthread.zig").sa_thread_raw_pthread_join;
// --- sa_std/regex.zig ---
pub const sa_regex_compile = @import("sa_std/regex.zig").sa_regex_compile; pub const sa_regex_match = @import("sa_std/regex.zig").sa_regex_match; pub const sa_regex_group_ptr = @import("sa_std/regex.zig").sa_regex_group_ptr; pub const sa_regex_group_len = @import("sa_std/regex.zig").sa_regex_group_len; pub const sa_regex_group_start = @import("sa_std/regex.zig").sa_regex_group_start; pub const sa_regex_group_count = @import("sa_std/regex.zig").sa_regex_group_count; pub const sa_regex_free = @import("sa_std/regex.zig").sa_regex_free; pub const sa_regex_match_free = @import("sa_std/regex.zig").sa_regex_match_free;
pub const sa_regex_match_all = @import("sa_std/regex.zig").sa_regex_match_all; pub const sa_regex_match_list_count = @import("sa_std/regex.zig").sa_regex_match_list_count; pub const sa_regex_match_list_at = @import("sa_std/regex.zig").sa_regex_match_list_at; pub const sa_regex_match_list_free = @import("sa_std/regex.zig").sa_regex_match_list_free; pub const sa_regex_replace = @import("sa_std/regex.zig").sa_regex_replace; pub const sa_regex_replace_all = @import("sa_std/regex.zig").sa_regex_replace_all; pub const sa_regex_buffer_data = @import("sa_std/regex.zig").sa_regex_buffer_data; pub const sa_regex_buffer_len = @import("sa_std/regex.zig").sa_regex_buffer_len;
pub const sa_regex_buffer_free = @import("sa_std/regex.zig").sa_regex_buffer_free; pub const sa_regex_split = @import("sa_std/regex.zig").sa_regex_split; pub const sa_regex_split_count = @import("sa_std/regex.zig").sa_regex_split_count; pub const sa_regex_split_ptr = @import("sa_std/regex.zig").sa_regex_split_ptr; pub const sa_regex_split_len = @import("sa_std/regex.zig").sa_regex_split_len; pub const sa_regex_split_free = @import("sa_std/regex.zig").sa_regex_split_free;
// --- sa_std/regex_core.zig ---
pub const RegexMatchHandle = @import("sa_std/regex_core.zig").RegexMatchHandle; pub const RegexMatchListHandle = @import("sa_std/regex_core.zig").RegexMatchListHandle; pub const RegexSplitListHandle = @import("sa_std/regex_core.zig").RegexSplitListHandle; pub const RegexBufferHandle = @import("sa_std/regex_core.zig").RegexBufferHandle; pub const regexErrorToZig = @import("sa_std/regex_core.zig").regexErrorToZig; pub const regexGroupCount = @import("sa_std/regex_core.zig").regexGroupCount; pub const regexMatchHandle = @import("sa_std/regex_core.zig").regexMatchHandle; pub const regexOwnedTextZ = @import("sa_std/regex_core.zig").regexOwnedTextZ;
pub const regexExecRange = @import("sa_std/regex_core.zig").regexExecRange; pub const regexCollectMatches = @import("sa_std/regex_core.zig").regexCollectMatches; pub const regexAppendGroup = @import("sa_std/regex_core.zig").regexAppendGroup; pub const regexAppendExpansion = @import("sa_std/regex_core.zig").regexAppendExpansion; pub const regexBuildReplace = @import("sa_std/regex_core.zig").regexBuildReplace; pub const regexSplitHandle = @import("sa_std/regex_core.zig").regexSplitHandle; pub const regexReplaceBuffer = @import("sa_std/regex_core.zig").regexReplaceBuffer;
// --- sa_std/sock_core.zig ---
pub const makeSockAddrStorage = @import("sa_std/sock_core.zig").makeSockAddrStorage; pub const UnixSockAddr = @import("sa_std/sock_core.zig").UnixSockAddr; pub const WasiMsghdr = @import("sa_std/sock_core.zig").WasiMsghdr; pub const MsghdrT = @import("sa_std/sock_core.zig").MsghdrT; pub const MsghdrConstT = @import("sa_std/sock_core.zig").MsghdrConstT; pub const msg_peek = @import("sa_std/sock_core.zig").msg_peek; pub const portableRecvmsg = @import("sa_std/sock_core.zig").portableRecvmsg; pub const UnixAddrHandle = @import("sa_std/sock_core.zig").UnixAddrHandle;
pub const unix_sockaddr_path_offset = @import("sa_std/sock_core.zig").unix_sockaddr_path_offset; pub const unixAddrFromSockaddr = @import("sa_std/sock_core.zig").unixAddrFromSockaddr; pub const registerUnixAddrOutLocked = @import("sa_std/sock_core.zig").registerUnixAddrOutLocked; pub const unixSockAddrFromHandle = @import("sa_std/sock_core.zig").unixSockAddrFromHandle; pub const TimevalSec = @import("sa_std/sock_core.zig").TimevalSec; pub const TimevalUsec = @import("sa_std/sock_core.zig").TimevalUsec; pub const timevalFromNs = @import("sa_std/sock_core.zig").timevalFromNs; pub const nsFromTimeval = @import("sa_std/sock_core.zig").nsFromTimeval;
pub const setSocketOptTimeval = @import("sa_std/sock_core.zig").setSocketOptTimeval; pub const getSocketOptBool = @import("sa_std/sock_core.zig").getSocketOptBool; pub const lxSetSocketOptBool = @import("sa_std/sock_core.zig").lxSetSocketOptBool; pub const rebuildTcpListenerV6Only = @import("sa_std/sock_core.zig").rebuildTcpListenerV6Only; pub const rebuildUdpSocketV6Only = @import("sa_std/sock_core.zig").rebuildUdpSocketV6Only; pub const getUnixPeerCred = @import("sa_std/sock_core.zig").getUnixPeerCred; pub const PeerCredSlot = @import("sa_std/sock_core.zig").PeerCredSlot; pub const peer_cred_slots = @import("sa_std/sock_core.zig").peer_cred_slots;
pub const peer_cred_cursor = @import("sa_std/sock_core.zig").peer_cred_cursor; pub const storeHarvestedPeerCredLocked = @import("sa_std/sock_core.zig").storeHarvestedPeerCredLocked; pub const harvestedPeerCredLocked = @import("sa_std/sock_core.zig").harvestedPeerCredLocked; pub const scmCredentials = @import("sa_std/sock_core.zig").scmCredentials; pub const getSocketOptTimeval = @import("sa_std/sock_core.zig").getSocketOptTimeval; pub const socketAddressFamily = @import("sa_std/sock_core.zig").socketAddressFamily; pub const socketIsUnix = @import("sa_std/sock_core.zig").socketIsUnix; pub const socketIsInet = @import("sa_std/sock_core.zig").socketIsInet;
pub const socketAcceptConn = @import("sa_std/sock_core.zig").socketAcceptConn; pub const ensureSocketHandle = @import("sa_std/sock_core.zig").ensureSocketHandle; pub const libc_socklen_t = @import("sa_std/sock_core.zig").libc_socklen_t; pub const lxBind = @import("sa_std/sock_core.zig").lxBind; pub const lxListen = @import("sa_std/sock_core.zig").lxListen; pub const lxConnect = @import("sa_std/sock_core.zig").lxConnect; pub const lxSendmsg = @import("sa_std/sock_core.zig").lxSendmsg; pub const lxFcntl = @import("sa_std/sock_core.zig").lxFcntl;
pub const lxGetsockname = @import("sa_std/sock_core.zig").lxGetsockname; pub const lxGetsockoptError = @import("sa_std/sock_core.zig").lxGetsockoptError; pub const cmsg_level_socket = @import("sa_std/sock_core.zig").cmsg_level_socket; pub const cmsgAlign = @import("sa_std/sock_core.zig").cmsgAlign; pub const tcpConnectToHostFd = @import("sa_std/sock_core.zig").tcpConnectToHostFd; pub const connectUnixSocketFd = @import("sa_std/sock_core.zig").connectUnixSocketFd; pub const tcpConnectAddressTimeout = @import("sa_std/sock_core.zig").tcpConnectAddressTimeout; pub const unixDatagramRecvFrom = @import("sa_std/sock_core.zig").unixDatagramRecvFrom;
// --- sa_std/sock_types.zig ---
pub const WasiSockAddrUn = @import("sa_std/sock_types.zig").WasiSockAddrUn; pub const WasiSockAddrIn = @import("sa_std/sock_types.zig").WasiSockAddrIn; pub const WasiSockAddrIn6 = @import("sa_std/sock_types.zig").WasiSockAddrIn6; pub const WasiSockAddrStorage = @import("sa_std/sock_types.zig").WasiSockAddrStorage; pub const WasiSockAddr = @import("sa_std/sock_types.zig").WasiSockAddr; pub const SockAddrUnT = @import("sa_std/sock_types.zig").SockAddrUnT; pub const SockAddrInT = @import("sa_std/sock_types.zig").SockAddrInT; pub const SockAddrIn6T = @import("sa_std/sock_types.zig").SockAddrIn6T;
pub const SockAddrStorageT = @import("sa_std/sock_types.zig").SockAddrStorageT; pub const SockAddrT = @import("sa_std/sock_types.zig").SockAddrT; pub const SockLenT = @import("sa_std/sock_types.zig").SockLenT; pub const WasiAF = @import("sa_std/sock_types.zig").WasiAF; pub const AFT = @import("sa_std/sock_types.zig").AFT; pub const WasiSOL = @import("sa_std/sock_types.zig").WasiSOL; pub const WasiSO = @import("sa_std/sock_types.zig").WasiSO; pub const SOT = @import("sa_std/sock_types.zig").SOT;
pub const WasiIPPROTO = @import("sa_std/sock_types.zig").WasiIPPROTO; pub const IPPROTOT = @import("sa_std/sock_types.zig").IPPROTOT; pub const WasiSOCK = @import("sa_std/sock_types.zig").WasiSOCK; pub const SOCKT = @import("sa_std/sock_types.zig").SOCKT; pub const TCP_QUICKACK = @import("sa_std/sock_types.zig").TCP_QUICKACK; pub const TCP_DEFER_ACCEPT = @import("sa_std/sock_types.zig").TCP_DEFER_ACCEPT; pub const TCP_KEEPIDLE = @import("sa_std/sock_types.zig").TCP_KEEPIDLE; pub const TCP_KEEPINTVL = @import("sa_std/sock_types.zig").TCP_KEEPINTVL;
pub const TCP_KEEPCNT = @import("sa_std/sock_types.zig").TCP_KEEPCNT; pub const SO_PASSCRED = @import("sa_std/sock_types.zig").SO_PASSCRED; pub const InAddrC = @import("sa_std/sock_types.zig").InAddrC; pub const IP_MULTICAST_TTL_OPT = @import("sa_std/sock_types.zig").IP_MULTICAST_TTL_OPT; pub const IP_MULTICAST_LOOP_OPT = @import("sa_std/sock_types.zig").IP_MULTICAST_LOOP_OPT; pub const IP_MULTICAST_IF_OPT = @import("sa_std/sock_types.zig").IP_MULTICAST_IF_OPT; pub const IP_ADD_MEMBERSHIP_OPT = @import("sa_std/sock_types.zig").IP_ADD_MEMBERSHIP_OPT; pub const IP_DROP_MEMBERSHIP_OPT = @import("sa_std/sock_types.zig").IP_DROP_MEMBERSHIP_OPT;
pub const IPV6_JOIN_GROUP_OPT = @import("sa_std/sock_types.zig").IPV6_JOIN_GROUP_OPT; pub const IPV6_LEAVE_GROUP_OPT = @import("sa_std/sock_types.zig").IPV6_LEAVE_GROUP_OPT; pub const IPV6_MULTICAST_HOPS_OPT = @import("sa_std/sock_types.zig").IPV6_MULTICAST_HOPS_OPT; pub const IPV6_MULTICAST_LOOP_OPT = @import("sa_std/sock_types.zig").IPV6_MULTICAST_LOOP_OPT; pub const IPV6_MULTICAST_IF_OPT = @import("sa_std/sock_types.zig").IPV6_MULTICAST_IF_OPT; pub const cmsg_level_ip = @import("sa_std/sock_types.zig").cmsg_level_ip; pub const cmsg_level_ipv6 = @import("sa_std/sock_types.zig").cmsg_level_ipv6; pub const cmsg_type_ip_pktinfo = @import("sa_std/sock_types.zig").cmsg_type_ip_pktinfo;
pub const cmsg_type_ipv6_pktinfo = @import("sa_std/sock_types.zig").cmsg_type_ipv6_pktinfo; pub const cmsg_type_timestamp = @import("sa_std/sock_types.zig").cmsg_type_timestamp;
// --- sa_std/spawn.zig ---
pub const WasiSIG = @import("sa_std/spawn.zig").WasiSIG; pub const SIGT = @import("sa_std/spawn.zig").SIGT; pub const FIRST_DYNAMIC_HANDLE = @import("sa_std/spawn.zig").FIRST_DYNAMIC_HANDLE; pub const constU32s = @import("sa_std/spawn.zig").constU32s; pub const dynamicIndex = @import("sa_std/spawn.zig").dynamicIndex; pub const takeResourceLocked = @import("sa_std/spawn.zig").takeResourceLocked; pub const killAndWaitChild = @import("sa_std/spawn.zig").killAndWaitChild; pub const envpFromCurrentProcess = @import("sa_std/spawn.zig").envpFromCurrentProcess;
pub const ProcessSpawnMode = @import("sa_std/spawn.zig").ProcessSpawnMode; pub const ProcessSpawnConfig = @import("sa_std/spawn.zig").ProcessSpawnConfig; pub const SpawnResult = @import("sa_std/spawn.zig").SpawnResult; pub const openPidfd = @import("sa_std/spawn.zig").openPidfd; pub const sendSignalToPidfd = @import("sa_std/spawn.zig").sendSignalToPidfd; pub const applyProcessCommandExtSetup = @import("sa_std/spawn.zig").applyProcessCommandExtSetup; pub const spawnProcessConfiguredCwd = @import("sa_std/spawn.zig").spawnProcessConfiguredCwd; pub const spawnProcessCwd = @import("sa_std/spawn.zig").spawnProcessCwd;
pub const spawnProcess = @import("sa_std/spawn.zig").spawnProcess; pub const lxErr = @import("sa_std/spawn.zig").lxErr; pub const lxDup2 = @import("sa_std/spawn.zig").lxDup2; pub const lxFork = @import("sa_std/spawn.zig").lxFork; pub const lxPipe2 = @import("sa_std/spawn.zig").lxPipe2; pub const lxChdir = @import("sa_std/spawn.zig").lxChdir; pub const lxChroot = @import("sa_std/spawn.zig").lxChroot; pub const lxSetgroups = @import("sa_std/spawn.zig").lxSetgroups;
pub const lxSetsid = @import("sa_std/spawn.zig").lxSetsid; pub const lxSetgid = @import("sa_std/spawn.zig").lxSetgid; pub const lxSetuid = @import("sa_std/spawn.zig").lxSetuid; pub const lxSetpgid = @import("sa_std/spawn.zig").lxSetpgid; pub const LxWaitResult = @import("sa_std/spawn.zig").LxWaitResult; pub const lxWaitpid = @import("sa_std/spawn.zig").lxWaitpid; pub const lxExecvpeZ = @import("sa_std/spawn.zig").lxExecvpeZ; pub const lxExit = @import("sa_std/spawn.zig").lxExit;
pub const sa_std_close = @import("sa_std/spawn.zig").sa_std_close; pub const sa_dl_close = @import("sa_std/spawn.zig").sa_dl_close; pub const processCommandExtConfig = @import("sa_std/spawn.zig").processCommandExtConfig; pub const sa_std_pidfd_kill = @import("sa_std/spawn.zig").sa_std_pidfd_kill; pub const sa_std_pidfd_send_signal = @import("sa_std/spawn.zig").sa_std_pidfd_send_signal; pub const sa_std_fd_into_raw = @import("sa_std/spawn.zig").sa_std_fd_into_raw;
// --- sa_std/std_fs.zig ---
pub const sa_std_fs_open_read = @import("sa_std/std_fs.zig").sa_std_fs_open_read; pub const sa_std_fs_open_write = @import("sa_std/std_fs.zig").sa_std_fs_open_write; pub const sa_std_fs_remove = @import("sa_std/std_fs.zig").sa_std_fs_remove; pub const sa_std_fs_exists = @import("sa_std/std_fs.zig").sa_std_fs_exists; pub const sa_std_fs_try_exists = @import("sa_std/std_fs.zig").sa_std_fs_try_exists; pub const sa_std_fs_len = @import("sa_std/std_fs.zig").sa_std_fs_len; pub const sa_std_fs_open_options = @import("sa_std/std_fs.zig").sa_std_fs_open_options; pub const sa_std_fs_open_create_excl = @import("sa_std/std_fs.zig").sa_std_fs_open_create_excl;
pub const sa_std_fs_file_from_raw_fd = @import("sa_std/std_fs.zig").sa_std_fs_file_from_raw_fd; pub const sa_std_fs_file_read = @import("sa_std/std_fs.zig").sa_std_fs_file_read; pub const sa_std_fs_file_read_at = @import("sa_std/std_fs.zig").sa_std_fs_file_read_at; pub const sa_std_fs_file_read_exact_at = @import("sa_std/std_fs.zig").sa_std_fs_file_read_exact_at; pub const sa_std_fs_file_write = @import("sa_std/std_fs.zig").sa_std_fs_file_write; pub const sa_std_fs_file_write_at = @import("sa_std/std_fs.zig").sa_std_fs_file_write_at; pub const sa_std_fs_file_write_all_at = @import("sa_std/std_fs.zig").sa_std_fs_file_write_all_at; pub const sa_std_fs_file_seek = @import("sa_std/std_fs.zig").sa_std_fs_file_seek;
pub const sa_std_fs_read_file = @import("sa_std/std_fs.zig").sa_std_fs_read_file; pub const sa_std_fs_read_to_string = @import("sa_std/std_fs.zig").sa_std_fs_read_to_string; pub const sa_std_fs_read_file_base64 = @import("sa_std/std_fs.zig").sa_std_fs_read_file_base64; pub const sa_std_fs_read_dir_json = @import("sa_std/std_fs.zig").sa_std_fs_read_dir_json; pub const sa_std_fs_read_dir_entries = @import("sa_std/std_fs.zig").sa_std_fs_read_dir_entries; pub const sa_std_fs_dir_entries_get = @import("sa_std/std_fs.zig").sa_std_fs_dir_entries_get; pub const sa_std_fs_metadata = @import("sa_std/std_fs.zig").sa_std_fs_metadata; pub const sa_std_fs_metadata_json = @import("sa_std/std_fs.zig").sa_std_fs_metadata_json;
pub const sa_std_fs_metadata_free = @import("sa_std/std_fs.zig").sa_std_fs_metadata_free; pub const sa_std_fs_canonicalize = @import("sa_std/std_fs.zig").sa_std_fs_canonicalize; pub const sa_std_fs_read_link = @import("sa_std/std_fs.zig").sa_std_fs_read_link;
// --- sa_std/std_net.zig ---
pub const sa_std_net_ja4_hash12 = @import("sa_std/std_net.zig").sa_std_net_ja4_hash12; pub const sa_std_net_error_code_from_status = @import("sa_std/std_net.zig").sa_std_net_error_code_from_status; pub const sa_std_net_error_code_from_posix_errno = @import("sa_std/std_net.zig").sa_std_net_error_code_from_posix_errno; pub const sa_std_net_error_code_from_wsa_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_wsa_error; pub const sa_std_net_error_code_name = @import("sa_std/std_net.zig").sa_std_net_error_code_name; pub const sa_std_net_error_platform = @import("sa_std/std_net.zig").sa_std_net_error_platform; pub const sa_std_net_error_code_from_native_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_native_error; pub const sa_std_net_hostname = @import("sa_std/std_net.zig").sa_std_net_hostname;
pub const sa_std_net_interface_addresses_json = @import("sa_std/std_net.zig").sa_std_net_interface_addresses_json; pub const sa_std_net_to_socket_addr_list = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_list; pub const sa_std_net_addr_list_next = @import("sa_std/std_net.zig").sa_std_net_addr_list_next; pub const sa_std_net_addr_list_remaining = @import("sa_std/std_net.zig").sa_std_net_addr_list_remaining; pub const sa_std_net_addr_list_reset = @import("sa_std/std_net.zig").sa_std_net_addr_list_reset; pub const sa_std_net_addr_list_free = @import("sa_std/std_net.zig").sa_std_net_addr_list_free; pub const sa_std_net_addr_reverse_lookup = @import("sa_std/std_net.zig").sa_std_net_addr_reverse_lookup; pub const sa_std_net_to_socket_addr_first = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_first;
pub const sa_std_net_poll_wait = @import("sa_std/std_net.zig").sa_std_net_poll_wait; pub const sa_std_net_raw_socket = @import("sa_std/std_net.zig").sa_std_net_raw_socket; pub const sa_std_net_socket_setsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt; pub const sa_std_net_socket_getsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt; pub const sa_std_net_socket_setsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt_int; pub const sa_std_net_socket_getsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt_int; pub const sa_std_net_addr_format = @import("sa_std/std_net.zig").sa_std_net_addr_format; pub const sa_std_net_ja3_hash = @import("sa_std/std_net.zig").sa_std_net_ja3_hash;
pub const sa_std_net_sha256_hex = @import("sa_std/std_net.zig").sa_std_net_sha256_hex;
// --- sa_std/std_net_tcp.zig ---
pub const sa_std_net_tcp_listener_set_reuseaddr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseaddr; pub const sa_std_net_tcp_listener_set_reuseport = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseport; pub const sa_std_net_tcp_listener_try_clone = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_try_clone; pub const sa_std_net_tcp_listener_set_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_only_v6; pub const sa_std_net_tcp_listener_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_only_v6; pub const sa_std_net_tcp_listener_set_nonblocking = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_nonblocking; pub const sa_std_net_tcp_listener_set_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_ttl; pub const sa_std_net_tcp_listener_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_ttl;
pub const sa_std_net_tcp_listener_take_error = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_take_error; pub const sa_std_net_tcp_listen = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listen; pub const sa_std_net_tcp_accept = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept; pub const sa_std_net_tcp_accept_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept_addr; pub const sa_std_net_tcp_listener_local_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_local_addr; pub const sa_std_net_tcp_listener_from_raw_fd = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_from_raw_fd; pub const sa_std_net_tcp_connect = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect; pub const sa_std_net_tcp_connect_timeout = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout;
pub const sa_std_net_tcp_connect_timeout_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_addr; pub const sa_std_net_tcp_connect_timeout_all = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_all;
// --- sa_std/std_net_tcp_stream.zig ---
pub const sa_std_net_tcp_stream_from_raw_fd = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_from_raw_fd; pub const sa_std_net_tcp_stream_read = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read; pub const sa_std_net_tcp_stream_read_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_vectored; pub const sa_std_net_tcp_stream_write_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_vectored; pub const sa_std_net_tcp_stream_peek = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peek; pub const sa_std_net_tcp_stream_write = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write; pub const sa_std_net_tcp_stream_peer_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peer_addr; pub const sa_std_net_tcp_stream_local_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_local_addr;
pub const sa_std_net_tcp_stream_try_clone = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_try_clone; pub const sa_std_net_tcp_stream_set_nonblocking = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nonblocking; pub const sa_std_net_tcp_stream_set_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nodelay; pub const sa_std_net_tcp_stream_set_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_linger; pub const sa_std_net_tcp_stream_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_linger; pub const sa_std_net_tcp_stream_set_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_quickack; pub const sa_std_net_tcp_stream_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_quickack; pub const sa_std_net_tcp_stream_set_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_deferaccept;
pub const sa_std_net_tcp_stream_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_deferaccept; pub const sa_std_net_tcp_stream_set_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive; pub const sa_std_net_tcp_stream_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_keepalive; pub const sa_std_net_tcp_stream_set_keepalive_params = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive_params; pub const sa_std_net_tcp_stream_set_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_read_timeout; pub const sa_std_net_tcp_stream_set_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_write_timeout; pub const sa_std_net_tcp_stream_set_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_ttl; pub const sa_std_net_tcp_stream_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_timeout;
pub const sa_std_net_tcp_stream_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_timeout; pub const sa_std_net_tcp_stream_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_nodelay; pub const sa_std_net_tcp_stream_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_ttl; pub const sa_std_net_tcp_stream_set_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_recv_buffer_size; pub const sa_std_net_tcp_stream_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_recv_buffer_size; pub const sa_std_net_tcp_stream_set_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_send_buffer_size; pub const sa_std_net_tcp_stream_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_buffer_size; pub const sa_std_net_tcp_stream_take_error = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_take_error;
pub const sa_std_net_tcp_stream_send_file = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_file;
// --- sa_std/std_net_udp.zig ---
pub const sa_std_net_udp_try_clone = @import("sa_std/std_net_udp.zig").sa_std_net_udp_try_clone; pub const sa_std_net_udp_bind = @import("sa_std/std_net_udp.zig").sa_std_net_udp_bind; pub const sa_std_net_udp_from_raw_fd = @import("sa_std/std_net_udp.zig").sa_std_net_udp_from_raw_fd; pub const sa_std_net_udp_local_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_local_addr; pub const sa_std_net_udp_peer_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peer_addr; pub const sa_std_net_udp_connect = @import("sa_std/std_net_udp.zig").sa_std_net_udp_connect; pub const sa_std_net_udp_connect_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_connect_addr; pub const sa_std_net_udp_only_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_only_v6;
pub const sa_std_net_udp_read_timeout = @import("sa_std/std_net_udp.zig").sa_std_net_udp_read_timeout; pub const sa_std_net_udp_write_timeout = @import("sa_std/std_net_udp.zig").sa_std_net_udp_write_timeout; pub const sa_std_net_udp_broadcast = @import("sa_std/std_net_udp.zig").sa_std_net_udp_broadcast; pub const sa_std_net_udp_join_multicast_v4 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v4; pub const sa_std_net_udp_leave_multicast_v4 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v4; pub const sa_std_net_udp_join_multicast_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v6; pub const sa_std_net_udp_leave_multicast_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v6; pub const sa_std_net_udp_ttl = @import("sa_std/std_net_udp.zig").sa_std_net_udp_ttl;
pub const sa_std_net_udp_take_error = @import("sa_std/std_net_udp.zig").sa_std_net_udp_take_error; pub const sa_std_net_udp_send = @import("sa_std/std_net_udp.zig").sa_std_net_udp_send; pub const sa_std_net_udp_recv = @import("sa_std/std_net_udp.zig").sa_std_net_udp_recv; pub const sa_std_net_udp_peek = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peek; pub const sa_std_net_udp_peek_from = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peek_from;
// --- sa_std/std_net_udp_io.zig ---
pub const sa_std_net_udp_recv_buffer_size = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_buffer_size; pub const sa_std_net_udp_send_buffer_size = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_buffer_size; pub const sa_std_net_udp_multicast_loop_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v4; pub const sa_std_net_udp_multicast_ttl_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_ttl_v4; pub const sa_std_net_udp_multicast_loop_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v6; pub const sa_std_net_udp_multicast_hops_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_hops_v6; pub const sa_std_net_udp_multicast_if_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v4; pub const sa_std_net_udp_multicast_if_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v6;
pub const sa_std_net_udp_send_to = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to; pub const sa_std_net_udp_recv_from = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from; pub const sa_std_net_udp_send_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_vectored; pub const sa_std_net_udp_send_to_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to_vectored; pub const sa_std_net_udp_recv_from_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from_vectored; pub const sa_std_net_udp_recv_msg = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_msg; pub const sa_std_net_udp_recv_multi = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_multi;
// --- sa_std/std_net_udp_set.zig ---
pub const sa_std_net_udp_set_only_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_only_v6; pub const sa_std_net_udp_set_nonblocking = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_nonblocking; pub const sa_std_net_udp_set_broadcast = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_broadcast; pub const sa_std_net_udp_set_ttl = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_ttl; pub const sa_std_net_udp_set_read_timeout = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_read_timeout; pub const sa_std_net_udp_set_write_timeout = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_write_timeout; pub const sa_std_net_udp_set_recv_buffer_size = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_recv_buffer_size; pub const sa_std_net_udp_set_send_buffer_size = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_send_buffer_size;
pub const sa_std_net_udp_set_multicast_loop_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v4; pub const sa_std_net_udp_set_multicast_ttl_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_ttl_v4; pub const sa_std_net_udp_set_multicast_loop_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v6; pub const sa_std_net_udp_set_multicast_hops_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_hops_v6; pub const sa_std_net_udp_set_multicast_if_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v4; pub const sa_std_net_udp_set_multicast_if_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v6;
// --- sa_std/std_net_unix.zig ---
pub const sa_std_net_unix_listen = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listen; pub const sa_std_net_unix_addr_from_abstract_name = @import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_abstract_name; pub const sa_std_net_unix_addr_from_pathname = @import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_pathname; pub const sa_std_net_unix_listen_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listen_addr; pub const sa_std_net_unix_accept = @import("sa_std/std_net_unix.zig").sa_std_net_unix_accept; pub const sa_std_net_unix_accept_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_accept_addr; pub const sa_std_net_unix_pair = @import("sa_std/std_net_unix.zig").sa_std_net_unix_pair; pub const sa_std_net_unix_listener_local_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_local_addr;
pub const sa_std_net_unix_listener_try_clone = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_try_clone; pub const sa_std_net_unix_listener_from_raw_fd = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_from_raw_fd; pub const sa_std_net_unix_stream_local_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_local_addr; pub const sa_std_net_unix_stream_try_clone = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_try_clone; pub const sa_std_net_unix_stream_from_raw_fd = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_from_raw_fd; pub const sa_std_net_unix_stream_peer_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_addr; pub const sa_std_net_unix_stream_set_passcred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_passcred; pub const sa_std_net_unix_stream_passcred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_passcred;
pub const sa_std_net_unix_stream_set_mark = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_mark; pub const sa_std_net_unix_stream_peer_cred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_cred; pub const sa_std_net_unix_connect = @import("sa_std/std_net_unix.zig").sa_std_net_unix_connect; pub const sa_std_net_unix_connect_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_connect_addr;
// --- sa_std/std_net_unix_dgram.zig ---
pub const sa_std_net_unix_datagram_peer_cred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_cred; pub const sa_std_net_unix_datagram_unbound = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_unbound; pub const sa_std_net_unix_datagram_bind = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind; pub const sa_std_net_unix_datagram_bind_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind_addr; pub const sa_std_net_unix_datagram_pair = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_pair; pub const sa_std_net_unix_datagram_connect = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect; pub const sa_std_net_unix_datagram_connect_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect_addr; pub const sa_std_net_unix_datagram_try_clone = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_try_clone;
pub const sa_std_net_unix_datagram_from_raw_fd = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_from_raw_fd; pub const sa_std_net_unix_datagram_local_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_local_addr; pub const sa_std_net_unix_datagram_peer_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_addr; pub const sa_std_net_unix_datagram_set_passcred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_passcred; pub const sa_std_net_unix_datagram_passcred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_passcred; pub const sa_std_net_unix_datagram_set_mark = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_mark; pub const sa_std_net_unix_datagram_shutdown = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_shutdown; pub const sa_std_net_unix_datagram_send_to = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to;
pub const sa_std_net_unix_datagram_send_to_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to_addr; pub const sa_std_net_unix_datagram_recv_from = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_recv_from; pub const sa_std_net_unix_datagram_peek_from = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peek_from;
// --- sa_std/std_process.zig ---
pub const sa_std_process_run = @import("sa_std/std_process.zig").sa_std_process_run; pub const sa_std_process_run_cwd = @import("sa_std/std_process.zig").sa_std_process_run_cwd; pub const sa_std_process_spawn = @import("sa_std/std_process.zig").sa_std_process_spawn; pub const sa_std_process_spawn_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_cwd; pub const sa_std_process_spawn_stream = @import("sa_std/std_process.zig").sa_std_process_spawn_stream; pub const sa_std_process_spawn_stream_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_cwd; pub const sa_std_process_spawn_bidi = @import("sa_std/std_process.zig").sa_std_process_spawn_bidi; pub const sa_std_process_spawn_bidi_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_bidi_cwd;
pub const sa_std_process_run_command_ext = @import("sa_std/std_process.zig").sa_std_process_run_command_ext; pub const sa_std_process_spawn_command_ext = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext; pub const sa_std_process_spawn_stream_command_ext = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext; pub const sa_std_process_run_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_pidfd; pub const sa_std_process_spawn_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_pidfd; pub const sa_std_process_spawn_stream_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_pidfd; pub const sa_std_process_run_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_uid_gid; pub const sa_std_process_spawn_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_uid_gid;
pub const sa_std_process_spawn_stream_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_uid_gid; pub const sa_std_process_run_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_groups; pub const sa_std_process_spawn_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_groups; pub const sa_std_process_spawn_stream_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_groups; pub const sa_std_process_run_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_chroot; pub const sa_std_process_spawn_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_chroot; pub const sa_std_process_spawn_stream_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_chroot; pub const sa_std_process_exec_command_ext = @import("sa_std/std_process.zig").sa_std_process_exec_command_ext;
pub const sa_std_process_id = @import("sa_std/std_process.zig").sa_std_process_id; pub const sa_std_process_parent_id = @import("sa_std/std_process.zig").sa_std_process_parent_id; pub const sa_std_process_user_id = @import("sa_std/std_process.zig").sa_std_process_user_id; pub const sa_std_process_group_id = @import("sa_std/std_process.zig").sa_std_process_group_id; pub const sa_std_process_abort = @import("sa_std/std_process.zig").sa_std_process_abort; pub const sa_std_process_child_id = @import("sa_std/std_process.zig").sa_std_process_child_id; pub const sa_std_process_wait = @import("sa_std/std_process.zig").sa_std_process_wait; pub const sa_std_process_wait_raw = @import("sa_std/std_process.zig").sa_std_process_wait_raw;
pub const sa_std_process_try_wait = @import("sa_std/std_process.zig").sa_std_process_try_wait; pub const sa_std_process_try_wait_raw = @import("sa_std/std_process.zig").sa_std_process_try_wait_raw; pub const sa_std_process_kill = @import("sa_std/std_process.zig").sa_std_process_kill; pub const sa_std_process_send_signal = @import("sa_std/std_process.zig").sa_std_process_send_signal; pub const sa_std_process_send_process_group_signal = @import("sa_std/std_process.zig").sa_std_process_send_process_group_signal; pub const sa_std_process_kill_process_group = @import("sa_std/std_process.zig").sa_std_process_kill_process_group; pub const sa_std_process_pidfd = @import("sa_std/std_process.zig").sa_std_process_pidfd; pub const sa_std_process_into_pidfd = @import("sa_std/std_process.zig").sa_std_process_into_pidfd;
pub const sa_std_process_exit_status_code = @import("sa_std/std_process.zig").sa_std_process_exit_status_code; pub const sa_std_process_exit_status_signal = @import("sa_std/std_process.zig").sa_std_process_exit_status_signal; pub const sa_std_process_exit_status_core_dumped = @import("sa_std/std_process.zig").sa_std_process_exit_status_core_dumped; pub const sa_std_process_exit_status_stopped_signal = @import("sa_std/std_process.zig").sa_std_process_exit_status_stopped_signal; pub const sa_std_process_exit_status_continued = @import("sa_std/std_process.zig").sa_std_process_exit_status_continued; pub const sa_std_process_read_stdout = @import("sa_std/std_process.zig").sa_std_process_read_stdout; pub const sa_std_process_read_stderr = @import("sa_std/std_process.zig").sa_std_process_read_stderr; pub const sa_std_process_exec_capture = @import("sa_std/std_process.zig").sa_std_process_exec_capture;
pub const sa_std_process_exec_capture_cwd = @import("sa_std/std_process.zig").sa_std_process_exec_capture_cwd; pub const sa_std_process_close = @import("sa_std/std_process.zig").sa_std_process_close;
// --- sa_std/str.zig ---
pub const sa_str_is_ascii = @import("sa_std/str.zig").sa_str_is_ascii; pub const sa_str_eq_ignore_ascii_case = @import("sa_std/str.zig").sa_str_eq_ignore_ascii_case; pub const sa_str_utf8_char_count = @import("sa_std/str.zig").sa_str_utf8_char_count; pub const sa_str_utf8_validate = @import("sa_std/str.zig").sa_str_utf8_validate; pub const sa_str_utf8_char_at = @import("sa_std/str.zig").sa_str_utf8_char_at; pub const sa_str_utf8_char_at_byte = @import("sa_std/str.zig").sa_str_utf8_char_at_byte; pub const sa_str_utf8_lossy_next = @import("sa_std/str.zig").sa_str_utf8_lossy_next; pub const sa_str_utf8_char_range_at = @import("sa_std/str.zig").sa_str_utf8_char_range_at;
pub const sa_str_trim_ascii_start_index = @import("sa_std/str.zig").sa_str_trim_ascii_start_index; pub const sa_str_trim_ascii_end_len = @import("sa_std/str.zig").sa_str_trim_ascii_end_len;
// --- sa_std/string.zig ---
pub const sa_string_concat = @import("sa_std/string.zig").sa_string_concat; pub const sa_string_from_char_code = @import("sa_std/string.zig").sa_string_from_char_code; pub const sa_string_index_of = @import("sa_std/string.zig").sa_string_index_of; pub const sa_string_last_index_of = @import("sa_std/string.zig").sa_string_last_index_of; pub const sa_string_starts_with = @import("sa_std/string.zig").sa_string_starts_with; pub const sa_string_ends_with = @import("sa_std/string.zig").sa_string_ends_with; pub const sa_string_to_lower_ascii = @import("sa_std/string.zig").sa_string_to_lower_ascii; pub const sa_string_to_upper_ascii = @import("sa_std/string.zig").sa_string_to_upper_ascii;
pub const sa_string_repeat = @import("sa_std/string.zig").sa_string_repeat; pub const sa_string_pad_start = @import("sa_std/string.zig").sa_string_pad_start; pub const sa_string_pad_end = @import("sa_std/string.zig").sa_string_pad_end; pub const sa_string_replace = @import("sa_std/string.zig").sa_string_replace; pub const sa_string_code_point_at = @import("sa_std/string.zig").sa_string_code_point_at; pub const sa_string_from_code_point = @import("sa_std/string.zig").sa_string_from_code_point;
// --- sa_std/term.zig ---
pub const sa_term_raw_enter = @import("sa_std/term.zig").sa_term_raw_enter; pub const sa_term_raw_leave = @import("sa_std/term.zig").sa_term_raw_leave; pub const sa_term_winsize = @import("sa_std/term.zig").sa_term_winsize; pub const sa_term_epoll_create = @import("sa_std/term.zig").sa_term_epoll_create; pub const sa_term_epoll_create_linux = @import("sa_std/term.zig").sa_term_epoll_create_linux; pub const sa_term_epoll_ctl = @import("sa_std/term.zig").sa_term_epoll_ctl; pub const sa_term_epoll_ctl_linux = @import("sa_std/term.zig").sa_term_epoll_ctl_linux; pub const sa_term_epoll_wait = @import("sa_std/term.zig").sa_term_epoll_wait;
pub const sa_term_epoll_wait_linux = @import("sa_std/term.zig").sa_term_epoll_wait_linux; pub const sa_term_epoll_close = @import("sa_std/term.zig").sa_term_epoll_close; pub const sa_term_epoll_close_linux = @import("sa_std/term.zig").sa_term_epoll_close_linux;
// --- sa_std/test_debug.zig ---
pub const TestDebugScalar = @import("sa_std/test_debug.zig").TestDebugScalar; pub const cryptoRandomU64 = @import("sa_std/test_debug.zig").cryptoRandomU64; pub const envValueFromCurrentProcess = @import("sa_std/test_debug.zig").envValueFromCurrentProcess; pub const envGetOwned = @import("sa_std/test_debug.zig").envGetOwned; pub const xdgHomeDirAlloc = @import("sa_std/test_debug.zig").xdgHomeDirAlloc; pub const xdgHomeSubdirAlloc = @import("sa_std/test_debug.zig").xdgHomeSubdirAlloc; pub const xdgDirsAlloc = @import("sa_std/test_debug.zig").xdgDirsAlloc; pub const tempRootAlloc = @import("sa_std/test_debug.zig").tempRootAlloc;
pub const tempPathAlloc = @import("sa_std/test_debug.zig").tempPathAlloc; pub const sa_test_debug_i64 = @import("sa_std/test_debug.zig").sa_test_debug_i64; pub const testTracePanicEnabled = @import("sa_std/test_debug.zig").testTracePanicEnabled; pub const printRecentTestScalars = @import("sa_std/test_debug.zig").printRecentTestScalars; pub const exitAfterAssertPanic = @import("sa_std/test_debug.zig").exitAfterAssertPanic; pub const sa_assert_eq_i64 = @import("sa_std/test_debug.zig").sa_assert_eq_i64; pub const sa_assert_eq_i64_at = @import("sa_std/test_debug.zig").sa_assert_eq_i64_at;
// --- sa_std/text_util.zig ---
pub const jsonKindOf = @import("sa_std/text_util.zig").jsonKindOf; pub const jsonValueAsF64 = @import("sa_std/text_util.zig").jsonValueAsF64; pub const jsonValueAsI64 = @import("sa_std/text_util.zig").jsonValueAsI64; pub const jsonValueAsBool = @import("sa_std/text_util.zig").jsonValueAsBool; pub const jsonValueClone = @import("sa_std/text_util.zig").jsonValueClone; pub const jsonWriterObjectFieldLocked = @import("sa_std/text_util.zig").jsonWriterObjectFieldLocked; pub const tokenTypeOf = @import("sa_std/text_util.zig").tokenTypeOf; pub const tokenTextSlice = @import("sa_std/text_util.zig").tokenTextSlice;
pub const formatInteger = @import("sa_std/text_util.zig").formatInteger; pub const formatFloat = @import("sa_std/text_util.zig").formatFloat; pub const formatBool = @import("sa_std/text_util.zig").formatBool; pub const formatBytes = @import("sa_std/text_util.zig").formatBytes; pub const jsonStringValue = @import("sa_std/text_util.zig").jsonStringValue; pub const appendEnvVarJson = @import("sa_std/text_util.zig").appendEnvVarJson; pub const hexSimdNibbleVal = @import("sa_std/text_util.zig").hexSimdNibbleVal; pub const sa_hexdec_simd = @import("sa_std/text_util.zig").sa_hexdec_simd;
pub const sa_mfind_u8 = @import("sa_std/text_util.zig").sa_mfind_u8; pub const appendPadded = @import("sa_std/text_util.zig").appendPadded; pub const appendIsoUtc = @import("sa_std/text_util.zig").appendIsoUtc; pub const appendTwo = @import("sa_std/text_util.zig").appendTwo; pub const appendFour = @import("sa_std/text_util.zig").appendFour; pub const formatIpv6Segments = @import("sa_std/text_util.zig").formatIpv6Segments; pub const utf8ScalarAt = @import("sa_std/text_util.zig").utf8ScalarAt; pub const utf8LossyInvalidWidth = @import("sa_std/text_util.zig").utf8LossyInvalidWidth;
pub const utf8CharRangeAt = @import("sa_std/text_util.zig").utf8CharRangeAt;
// --- sa_std/time.zig ---
pub const sa_time_instant_ns = @import("sa_std/time.zig").sa_time_instant_ns; pub const sa_time_unix_s = @import("sa_std/time.zig").sa_time_unix_s; pub const sa_time_unix_ms = @import("sa_std/time.zig").sa_time_unix_ms; pub const sa_time_iso_from_unix_ms = @import("sa_std/time.zig").sa_time_iso_from_unix_ms; pub const sa_time_parse_iso = @import("sa_std/time.zig").sa_time_parse_iso; pub const sa_time_get_full_year = @import("sa_std/time.zig").sa_time_get_full_year; pub const sa_time_get_month = @import("sa_std/time.zig").sa_time_get_month; pub const sa_time_get_date = @import("sa_std/time.zig").sa_time_get_date;
pub const sa_time_get_hours = @import("sa_std/time.zig").sa_time_get_hours; pub const sa_time_get_minutes = @import("sa_std/time.zig").sa_time_get_minutes; pub const sa_time_get_seconds = @import("sa_std/time.zig").sa_time_get_seconds; pub const sa_time_get_milliseconds = @import("sa_std/time.zig").sa_time_get_milliseconds; pub const sa_time_get_day = @import("sa_std/time.zig").sa_time_get_day; pub const sa_time_format_utc = @import("sa_std/time.zig").sa_time_format_utc; pub const sa_time_set_field = @import("sa_std/time.zig").sa_time_set_field; pub const sa_time_unix_ns = @import("sa_std/time.zig").sa_time_unix_ns;
pub const sa_time_utc_now = @import("sa_std/time.zig").sa_time_utc_now; pub const sa_time_sleep_ns = @import("sa_std/time.zig").sa_time_sleep_ns; pub const sa_time_sleep_ms = @import("sa_std/time.zig").sa_time_sleep_ms;




// Runtime permission gate (sala 16_policy): checked at resource
// acquisition points only. No context installed -> allowed (the
// host surface enforces "no policy, no start"). Denial returns the
// dedicated SA_STD_ERR_PERMISSION_DENIED status; getters without a
// status channel (env, time, random) deny by returning zero, and
// every denial is audit-logged through the installed sink.

// Run-category policy check shared with satellite runtime files
// (sa_pty.zig): a PTY spawn acquires a process exactly like the spawn
// funnel above, so it goes through the same 16_policy gate.

// Fs-read policy check shared with satellite runtime files
// (sa_fs_watch.zig): registering a watch is a read-side acquisition.

// ---------------------------------------------------------------------
// Policy bootstrap for produced binaries (sala 16_policy phase 1,
// slice 3). The deployment supplies the policy through the
// environment; an ELF constructor installs it before main runs:
//   SA_POLICY_JSON      inline policy JSON (highest priority)
//   SA_POLICY_TOKENS_JSON  one-time token specs minted into the root context
//   SA_POLICY_FILE      path to a policy JSON file
//   SA_POLICY_ALLOW_ALL "1" engages an explicit allow-all policy (the
//                       -A analog) and always leaves an audit trace
//   SA_POLICY_REQUIRED  "1" with none of the above: refuse to start
//   SA_AUDIT_FILE       audit JSONL destination; otherwise the
//                       policy's audit.sink file:// path; otherwise
//                       audit events are dropped
// With nothing set, no context is installed and the process runs in
// legacy mode; SA_POLICY_REQUIRED is how a deployment closes that
// door. A policy that is present but unreadable or invalid is a hard
// startup failure, never a silent fallback to legacy mode.

pub var policy_audit_fd: ?std.posix.fd_t = null;

// ---------------------------------------------------------------------
// DEF-R7: SIGPIPE policy (Jev ruling 2026-10-31:
// ignore_at_startup_surface_epipe / host_startup_all). Every SA-built
// program ignores SIGPIPE from startup, before user code runs, so a
// write to a closed peer surfaces through the existing status
// discipline (error.BrokenPipe -> SA_STD_ERR_IO on the fd/tcp faces,
// NetworkStatus.closed on the http faces) instead of killing the
// whole process. Before this, the only protection was incidental:
// std.Io.Threaded.init installs a do-nothing SIGPIPE handler the
// first time sio.io() is called — any write path reached before that
// init (or after a Threaded deinit restores SIG_DFL, or on the
// single-threaded Io variant, which installs nothing) died with
// signal 13. Installation rides the existing policy-bootstrap ELF
// constructor (.init_array below), which runs before main in every
// produced binary that links this archive object; the host process
// installs the same disposition at its own main (src/main.zig).
// Only SIGPIPE is touched; no other signal's disposition changes.

// DEF-R7 startup entry called by every generated program main
// wrapper (LLVM shim + C backend) before user code runs. This is
// the coverage backbone: a plain reference from the wrapper extracts
// this archive object at link time even for programs that reference
// no other sa_std symbol, where the .init_array constructor alone
// would never be linked in. Exported on all targets; the install
// itself no-ops where SIGPIPE does not exist (wasm/windows).

// align(8) is load-bearing: with a larger section alignment the linker
// pads .init_array up to the boundary, and glibc's init walk calls that
// zero padding as a null function pointer before main ever runs.

comptime {
    if (!builtin.is_test and builtin.os.tag == .linux and !is_wasm) {
        @export(&policyBootstrap, .{ .name = "sa_policy_bootstrap" });
        @export(&policy.policy_bootstrap_init_entry, .{ .name = "__sa_policy_bootstrap_init" });
    }
}
// Pull the new sa_std protocol runtimes (http2/tls_server/dtls/quic) export
// functions into the library object. Zig only emits `pub export fn`s of a
// transitively-imported module when the root source actually retains the
// module's declaration, so a comptime reference block forces every export fn
// here to be kept and emitted into libsa_std alongside the rest of the sa_std
// surface. This is purely a link-time union; nothing calls these directly.
comptime {
    @setEvalBranchQuota(100000);
    const http2 = @import("sa_http2.zig");
    _ = &http2.sa_std_http2_supported;
    _ = &http2.sa_std_http2_client_request;
    _ = &http2.sa_std_http2_client_request_with_settings;
    _ = &http2.sa_std_http2_nghttp2_version_json;
    _ = &http2.sa_std_http2_status_json;
    _ = &http2.sa_std_http2_constants_json;
    _ = &http2.sa_std_http2_sensitive_headers;
    _ = &http2.sa_std_http2_get_default_settings_json;
    _ = &http2.sa_std_http2_get_packed_settings;
    _ = &http2.sa_std_http2_get_unpacked_settings_json;
    _ = &http2.sa_std_http2_perform_server_handshake;
    _ = &http2.sa_std_http2_buffer_data;
    _ = &http2.sa_std_http2_buffer_len;
    _ = &http2.sa_std_http2_buffer_free;
    _ = &sa_globals.sa_global_u64_set;
    _ = &sa_globals.sa_global_u64_get;
    _ = &sa_globals.sa_global_u64_set_once;
    _ = &sa_globals.sa_global_u64_add;
    _ = &sa_globals.sa_global_bytes_set;
    _ = &sa_globals.sa_global_bytes_get;
    _ = &sa_identity.sa_idmap_new;
    _ = &sa_identity.sa_idmap_free;
    _ = &sa_identity.sa_idmap_set;
    _ = &sa_identity.sa_idmap_get;
    _ = &sa_identity.sa_idmap_set_u64;
    _ = &sa_identity.sa_idmap_get_u64;
    _ = &sa_identity.sa_idmap_has;
    _ = &sa_identity.sa_idmap_remove;
    _ = &sa_identity.sa_idmap_len;
    _ = &sa_identity.sa_idmap_clear;
    _ = &sa_identity.sa_idset_new;
    _ = &sa_identity.sa_idset_free;
    _ = &sa_identity.sa_idset_add;
    _ = &sa_identity.sa_idset_has;
    _ = &sa_identity.sa_idset_remove;
    _ = &sa_identity.sa_idset_len;
    _ = &sa_identity.sa_idset_clear;
    _ = &@import("sa_compress.zig").sa_std_compress_encode;
    _ = &@import("sa_dtls.zig").sa_std_dtls_supported;
    _ = &@import("sa_multipart.zig").sa_std_multipart_parse;
    _ = &@import("sa_multipart.zig").sa_std_multipart_builder_new;
    _ = &@import("sa_ssh.zig").sa_std_ssh_client_connect;
    _ = &@import("sa_ssh.zig").sa_std_ssh_server_listen;
    _ = &@import("sa_thread_local.zig").sa_thread_local_supported;
    _ = &@import("sa_ws_client.zig").sa_std_ws_client_supported;
    { const m = @import("sa_cookie.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_crypto.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_crypto_asym.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_fs_watch.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_http_client.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_http_server.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_mysql_client.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_pg.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_pty.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_quic.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/deno.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/env.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/fmt.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/fs.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/fs_meta.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/io.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/json_io.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/math.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/net.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/regex.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_fs.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_tcp.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_tcp_stream.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_udp.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_udp_io.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_udp_set.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_unix.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_net_unix_dgram.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_process.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/std_process_spawn.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/str.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/string.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/term.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/time.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_tls_client.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_tls_server.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_tls_shaped.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_toml.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_tree_sitter.zig"); for (std.meta.declarations(m)) |n| { if (!std.mem.eql(u8, n, "setTsDir")) _ = &@field(m, n); } }
    { const m = @import("sa_yaml.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/b64_simd.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/core_export.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/core_misc.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/core_misc2.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/dlopen.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/fallible.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/fd_core.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/io_plan.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/policy.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/proc_wait.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/spawn.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/test_debug.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    { const m = @import("sa_std/text_util.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    // force-emit all fns of sa_crypto_keyring.zig (loop over decls)
    {
        const m = @import("sa_crypto_keyring.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_crypto_sign.zig (loop over decls)
    {
        const m = @import("sa_crypto_sign.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tree_sitter_node.zig (loop over decls)
    {
        const m = @import("sa_tree_sitter_node.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tree_sitter_query.zig (loop over decls)
    {
        const m = @import("sa_tree_sitter_query.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tls_client_config.zig (loop over decls)
    {
        const m = @import("sa_tls_client_config.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tls_client_handshake.zig (loop over decls)
    {
        const m = @import("sa_tls_client_handshake.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_http2_buffer.zig (loop over decls)
    {
        const m = @import("sa_http2_buffer.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_pg_bind.zig (loop over decls)
    {
        const m = @import("sa_pg_bind.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_pg_result.zig (loop over decls)
    {
        const m = @import("sa_pg_result.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_crypto_asym_keygen.zig (loop over decls)
    {
        const m = @import("sa_crypto_asym_keygen.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_crypto_asym_x509.zig (loop over decls)
    {
        const m = @import("sa_crypto_asym_x509.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    if (builtin.os.tag == .linux) {
    }
    _ = &sa_task.sa_task_spawn;
    _ = &sa_task.sa_task_detach;
    _ = &sa_task.sa_chan_make;
    _ = &sa_task.sa_chan_select;
    _ = &sa_task.sa_task_net_wait;
    _ = &sa_task.sa_sync_mutex_new;
    _ = &sa_task.sa_sync_waitgroup_new;
    _ = &sa_task.sa_sync_once_new;
    { const m = @import("sa_std/json.zig"); for (std.meta.declarations(m)) |n| _ = &@field(m, n); }
    if (builtin.os.tag == .linux) {
        _ = &@import("sa_net_uring.zig").sa_netx_init;
    }
}

extern fn regcomp(preg: ?*RegexC, pattern: [*c]const u8, cflags: c_int) c_int;
extern fn regexec(preg: ?*const RegexC, text: [*c]const u8, nmatch: usize, pmatch: [*]RegexMatchC, eflags: c_int) c_int;
extern fn regfree(preg: ?*RegexC) void;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

extern "c" var environ: [*:null]?[*:0]u8;

comptime {
    // wasm32-wasi: c_ulong/usize are 32-bit (vs 64-bit on x86_64-linux),
    // so RegexC layout differs. Only assert native glibc layout on non-wasm.
    if (!builtin.cpu.arch.isWasm()) {
        std.debug.assert(@sizeOf(RegexC) == 64);
        std.debug.assert(@alignOf(RegexC) == 8);
        std.debug.assert(@offsetOf(RegexC, "re_nsub") == 48);
        std.debug.assert(@offsetOf(RegexC, "flags") == 56);
        std.debug.assert(@sizeOf(RegexMatchC) == 8);
        std.debug.assert(@offsetOf(RegexMatchC, "rm_so") == 0);
        std.debug.assert(@offsetOf(RegexMatchC, "rm_eo") == 4);
    }
}
extern fn uname(buf: *fbsd_utsname) c_int;
extern fn if_nametoindex(ifname: [*:0]const u8) c_uint;
// Non-Linux targets call libc recvmsg directly. Note: the extern name must be
// exactly "recvmsg" — macOS dylibs reject undefined symbols, unlike ELF .so.
extern "c" fn recvmsg(sockfd: std.posix.fd_t, msg: *MsghdrT, flags: c_int) isize;
extern "c" fn __error() *c_int;

pub var registry_mutex: std.atomic.Mutex = .unlocked;
pub threadlocal var last_error: i32 = SA_STD_OK;

extern fn sa_host_pthread_create(thread: *std.c.pthread_t, attr: ?*const std.c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_join(thread: std.c.pthread_t, retval: ?*?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_detach(thread: std.c.pthread_t) callconv(.c) c_int;

// SIMD base64 decoder: native bulk-decode fast path. Decodes clean
// A-Za-z0-9+/ quanta at 32 input chars per vector iteration with a
// scalar tail. Stops at the first non-alphabet char (including '=')
// and returns the bytes written so far; clean input of n chars with
// n % 4 == 0 yields exactly n/4*3. Caller must provide that many bytes.

extern fn sa_cpu_has_avx2() c_int;
extern fn sa_b64dec_avx2(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64;

extern fn getifaddrs(ifap: *?*struct_ifaddrs) c_int;
extern fn freeifaddrs(ifa: ?*struct_ifaddrs) void;
extern fn inet_ntop(af: c_int, src: ?*const anyopaque, dst: [*]u8, size: c_uint) ?[*:0]const u8;

pub extern fn getpid() c_int;
extern fn getppid() c_int;
pub extern fn getuid() c_uint;
pub extern fn getgid() c_uint;
extern fn getpagesize() c_int;

// ---- local network information: interface address snapshot ----
//
// Backs sa_std/net_info.sai (sa_std_net_interface_addresses_json).
// The Deno compatibility walk above (sa_deno_network_interfaces)
// proves the getifaddrs linkage, but its result shape is Deno's:
// string families, a "cidr" string, a hard-coded fallback netmask
// and no status code. This is the sa_std-shaped snapshot: one JSON
// array in an owned byte buffer (the sa_std_fs_read_dir_json
// result convention), numeric address families, an explicit
// prefix_len, the broadcast address when the kernel reports one,
// and an SA_STD_* status return. The SLA layer in
// sa_std/net_info.sla parses the snapshot with the sa_json
// document surface and joins it with the /sys/class/net interface
// records and the /proc route tables.
//
// Not declared in sa_std.h (SLA-first surface, cookie/TOML
// precedent), so the runtime-abi-check header counts are
// unchanged. Linux only for now; the Windows runtime mirror does
// not implement the symbol yet.

// ---------------------------------------------------------------------------
// Unicode normalization (ICU unorm2) for tsgosa String.prototype.normalize.
// Form codes (JEV i32_code): 0 = NFC, 1 = NFD, 2 = NFKC, 3 = NFKD.
// Two-pass length protocol (JEV two_pass_len): call with out_cap == 0 to
// query the needed UTF-8 byte length (nothing written); call again with a
// buffer of at least that size to fill it. If the buffer is too small, the
// function writes nothing and returns the needed length. Invalid form codes
// and invalid UTF-8 input panic (JEV runtime_panic: the SA shape closest to
// JS RangeError). Embedded NUL bytes are fine (all lengths explicit).
// ICU error contract (U_FAILURE semantics): codes > 0 are failures, codes
// <= 0 are success -- negative codes are WARNINGS, not failures. In
// particular U_STRING_NOT_TERMINATED_WARNING (-124) is set when the
// destination is exactly full (content correct, no room for the NUL
// terminator). Every check below is therefore err > 0, never err != 0;
// treating -124 as failure would panic on every exact-fit call (e.g.
// all-ASCII input, or the SA wrapper filling an exactly-sized buffer).
// ICU 74 symbol versioning: the C headers rename these entry points with
// a _74 suffix (U_ICU_VERSION_SUFFIX); Zig extern declarations must use
// the real suffixed symbol. Bumping the ICU major requires renaming
// the seven declarations below.
// NOTE: the SA interpreter cannot run externs (UnsupportedExtern); this
// function executes under build-exe (LLVM) and is unit-tested directly.
// The JS target gets a shim in emit_js.zig (JEV js_shim).
extern fn unorm2_getNFCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFDInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKDInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_normalize_74(norm2: ?*anyopaque, src: [*]const u16, src_len: c_int, dest: [*]u16, dest_cap: c_int, err: *c_int) c_int;
extern fn u_strFromUTF8_74(dest: [*]u16, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u8, src_len: c_int, err: *c_int) ?[*]u16;
extern fn u_strToUTF8_74(dest: ?[*]u8, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u16, src_len: c_int, err: *c_int) ?[*]u8;

comptime {
    if (!builtin.is_test) {
        @export(&fd_open, .{ .name = "fd_open" });
        @export(&fd_read, .{ .name = "fd_read" });
        @export(&fd_close, .{ .name = "fd_close" });
        @export(&pthread_spawn, .{ .name = "pthread_spawn" });
        @export(&pthread_spawn_detached, .{ .name = "pthread_spawn_detached" });
        // The SA-facing join is exported ONLY under the non-colliding
        // name sa_pthread_join (see thread.sai): the definition's
        // handle-registry ABI is not libc's pthread_join signature.
        // Under the bare name it captured std.Thread's joins when
        // exported (the F1 incident class below) and, once gated to
        // no-libc targets, SA programs fell through to glibc's
        // pthread_join and segfaulted on the slot id.
        @export(&pthread_join, .{ .name = "sa_pthread_join" });
        @export(&pthread_drop, .{ .name = "pthread_drop" });
        @export(&sa_thread_as_pthread_t, .{ .name = "sa_thread_as_pthread_t" });
        @export(&sa_thread_into_pthread_t, .{ .name = "sa_thread_into_pthread_t" });
        @export(&sa_thread_raw_pthread_join, .{ .name = "sa_thread_raw_pthread_join" });
        // The dl* compatibility definitions must only be exported where the
        // target has no real libc dlopen (wasi / no-libc links). On libc
        // targets they capture std.DynLib's extern references at link time
        // (hidden visibility does not prevent archive-member binding), which
        // silently replaced every runtime dlopen with the cookie stub:
        // brotli/QUIC/TLS loaders degraded and SSH crashed calling the
        // cookie address from SA-produced binaries. Test builds never saw
        // it because this block is skipped under builtin.is_test.
        //
        // The same capture applies to every other compatibility definition
        // whose name collides with a libc symbol, so they share the dl*
        // gate: mmap/munmap (the page allocator's extern references bound
        // to the no-op stub — an 8,000-request HTTP client loop issued
        // 120,066 mmap syscalls against exactly 1 munmap, growing RSS
        // without bound in slanginx/slaredis-class long-running
        // executables), signal (stub installs no handler), pthread_join
        // (the bare libc name stays gated to no-libc targets as a compat
        // surface; SA programs use sa_pthread_join, exported above —
        // the handle-registry ABI is not the libc signature std.Thread
        // joins through), and the sqlite3_* stubs (would shadow a real
        // libsqlite3 in the same link).
        if (builtin.os.tag == .wasi or !builtin.link_libc) {
            @export(&dlopen, .{ .name = "dlopen", .visibility = .hidden });
            @export(&dlsym, .{ .name = "dlsym", .visibility = .hidden });
            @export(&dlclose, .{ .name = "dlclose", .visibility = .hidden });
            // mmap/munmap are weak on top of hidden: hidden alone still
            // collides at link time when a client object referencing the
            // real libc mmap/munmap (e.g. an SA-implemented std unit such
            // as GrowVec) pulls libc's mman.o into a link that also pulls
            // this compilation unit -- wasm-ld reports a duplicate symbol
            // against the stub. Weak lets the real libc definition win
            // whenever one is present in the link, while the stub still
            // serves links with no libc at all. References from inside
            // this unit (the page allocator) bind locally either way.
            @export(&mmap, .{ .name = "mmap", .visibility = .hidden, .linkage = .weak });
            @export(&munmap, .{ .name = "munmap", .visibility = .hidden, .linkage = .weak });
            @export(&signal, .{ .name = "signal", .visibility = .hidden });
            @export(&pthread_join, .{ .name = "pthread_join", .visibility = .hidden });
            @export(&sqlite3_prepare, .{ .name = "sqlite3_prepare", .visibility = .hidden });
            @export(&sqlite3_step, .{ .name = "sqlite3_step", .visibility = .hidden });
            @export(&sqlite3_finalize, .{ .name = "sqlite3_finalize", .visibility = .hidden });
        }
    }
}
