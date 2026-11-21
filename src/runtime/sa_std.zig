const std = @import("std");
const spawn = @import("sa_std/spawn.zig");
const policy = @import("sa_std/policy.zig");
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
// --- sa_std/deno.zig ---
pub const sa_deno_cwd = @import("sa_std/deno.zig").sa_deno_cwd; pub const sa_deno_chdir = @import("sa_std/deno.zig").sa_deno_chdir; pub const sa_deno_env_set = @import("sa_std/deno.zig").sa_deno_env_set; pub const sa_deno_env_delete = @import("sa_std/deno.zig").sa_deno_env_delete; pub const sa_deno_random_uuid = @import("sa_std/deno.zig").sa_deno_random_uuid; pub const sa_deno_make_temp_dir = @import("sa_std/deno.zig").sa_deno_make_temp_dir; pub const sa_deno_make_temp_file = @import("sa_std/deno.zig").sa_deno_make_temp_file; pub const sa_deno_args_json = @import("sa_std/deno.zig").sa_deno_args_json;
pub const sa_deno_btoa = @import("sa_std/deno.zig").sa_deno_btoa; pub const sa_deno_atob = @import("sa_std/deno.zig").sa_deno_atob; pub const sa_deno_text_encode = @import("sa_std/deno.zig").sa_deno_text_encode; pub const sa_deno_text_decode = @import("sa_std/deno.zig").sa_deno_text_decode; pub const sa_deno_chat_sse_to_responses = @import("sa_std/deno.zig").sa_deno_chat_sse_to_responses; pub const sa_deno_chat_json_to_responses = @import("sa_std/deno.zig").sa_deno_chat_json_to_responses; pub const sa_deno_responses_sse_normalize = @import("sa_std/deno.zig").sa_deno_responses_sse_normalize; pub const sa_deno_responses_json_normalize = @import("sa_std/deno.zig").sa_deno_responses_json_normalize;
pub const sa_deno_responses_request_normalize = @import("sa_std/deno.zig").sa_deno_responses_request_normalize; pub const sa_deno_responses_chat_fallback_request = @import("sa_std/deno.zig").sa_deno_responses_chat_fallback_request; pub const sa_deno_jsonrpc_params_string_literal = @import("sa_std/deno.zig").sa_deno_jsonrpc_params_string_literal; pub const sa_deno_version_json = @import("sa_std/deno.zig").sa_deno_version_json; pub const sa_deno_version_deno = @import("sa_std/deno.zig").sa_deno_version_deno; pub const sa_deno_build_json = @import("sa_std/deno.zig").sa_deno_build_json; pub const sa_deno_build_os = @import("sa_std/deno.zig").sa_deno_build_os; pub const sa_deno_build_platform_family = @import("sa_std/deno.zig").sa_deno_build_platform_family;
pub const sa_deno_date_now_iso = @import("sa_std/deno.zig").sa_deno_date_now_iso; pub const sa_deno_hostname = @import("sa_std/deno.zig").sa_deno_hostname; pub const sa_deno_os_release = @import("sa_std/deno.zig").sa_deno_os_release; pub const sa_deno_os_uptime = @import("sa_std/deno.zig").sa_deno_os_uptime; pub const sa_deno_loadavg = @import("sa_std/deno.zig").sa_deno_loadavg; pub const sa_deno_system_memory_info = @import("sa_std/deno.zig").sa_deno_system_memory_info; pub const sa_deno_network_interfaces = @import("sa_std/deno.zig").sa_deno_network_interfaces; pub const sa_deno_pid = @import("sa_std/deno.zig").sa_deno_pid;
pub const sa_deno_ppid = @import("sa_std/deno.zig").sa_deno_ppid; pub const sa_deno_uid = @import("sa_std/deno.zig").sa_deno_uid; pub const sa_deno_gid = @import("sa_std/deno.zig").sa_deno_gid; pub const sa_deno_exec_path = @import("sa_std/deno.zig").sa_deno_exec_path; pub const sa_deno_memory_usage = @import("sa_std/deno.zig").sa_deno_memory_usage;
// --- sa_std/dir_stat.zig ---
pub const MetadataHandle = @import("sa_std/dir_stat.zig").MetadataHandle; pub const DirEntrySnapshot = @import("sa_std/dir_stat.zig").DirEntrySnapshot; pub const DirEntriesHandle = @import("sa_std/dir_stat.zig").DirEntriesHandle; pub const statTimeFieldName = @import("sa_std/dir_stat.zig").statTimeFieldName; pub const timeSpecMs = @import("sa_std/dir_stat.zig").timeSpecMs; pub const metadataU64Field = @import("sa_std/dir_stat.zig").metadataU64Field; pub const metadataI64TimeFieldMs = @import("sa_std/dir_stat.zig").metadataI64TimeFieldMs; pub const metadataI64TimeFieldSec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldSec;
pub const metadataI64TimeFieldNsec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldNsec; pub const RawStat = @import("sa_std/dir_stat.zig").RawStat; pub const timestampToRawTs = @import("sa_std/dir_stat.zig").timestampToRawTs; pub const kindModeBits = @import("sa_std/dir_stat.zig").kindModeBits; pub const rawStatFromIo = @import("sa_std/dir_stat.zig").rawStatFromIo; pub const lxStatxNoFollow = @import("sa_std/dir_stat.zig").lxStatxNoFollow; pub const statFromRaw = @import("sa_std/dir_stat.zig").statFromRaw; pub const statxDevId = @import("sa_std/dir_stat.zig").statxDevId;
pub const tsToMs = @import("sa_std/dir_stat.zig").tsToMs; pub const writeJsonBoolField = @import("sa_std/dir_stat.zig").writeJsonBoolField; pub const nsToMs = @import("sa_std/dir_stat.zig").nsToMs; pub const writeJsonIntField = @import("sa_std/dir_stat.zig").writeJsonIntField; pub const writeMetadataJson = @import("sa_std/dir_stat.zig").writeMetadataJson; pub const writeMetadataJsonExt = @import("sa_std/dir_stat.zig").writeMetadataJsonExt; pub const dirEntryKindFromLinuxType = @import("sa_std/dir_stat.zig").dirEntryKindFromLinuxType; pub const dirEntryKindFromIo = @import("sa_std/dir_stat.zig").dirEntryKindFromIo;
pub const readDirEntriesLinux = @import("sa_std/dir_stat.zig").readDirEntriesLinux;
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
pub const policyBootstrapWriteStderr = @import("sa_std/policy.zig").policyBootstrapWriteStderr; pub const policyAuditSink = @import("sa_std/policy.zig").policyAuditSink; pub const policyBootstrapFail = @import("sa_std/policy.zig").policyBootstrapFail; pub const policyEnvFlag = @import("sa_std/policy.zig").policyEnvFlag; pub const installPolicyText = @import("sa_std/policy.zig").installPolicyText; pub const applySigpipeIgnore = @import("sa_std/policy.zig").applySigpipeIgnore; pub const installSigpipeIgnore = @import("sa_std/policy.zig").installSigpipeIgnore; pub const sa_install_sigpipe_ignore = @import("sa_std/policy.zig").sa_install_sigpipe_ignore;
pub const policyBootstrap = @import("sa_std/policy.zig").policyBootstrap;
// --- sa_std/proc_wait.zig ---
pub const WasiW = @import("sa_std/proc_wait.zig").WasiW; pub const WT = @import("sa_std/proc_wait.zig").WT; pub const w_exited = @import("sa_std/proc_wait.zig").w_exited; pub const w_nohang = @import("sa_std/proc_wait.zig").w_nohang; pub const ProcessHandle = @import("sa_std/proc_wait.zig").ProcessHandle; pub const capture_fd_to_owned = @import("sa_std/proc_wait.zig").capture_fd_to_owned; pub const statusFromWaitStatus = @import("sa_std/proc_wait.zig").statusFromWaitStatus; pub const rawWaitStatus = @import("sa_std/proc_wait.zig").rawWaitStatus;
pub const waitStatusCode = @import("sa_std/proc_wait.zig").waitStatusCode; pub const waitStatusSignal = @import("sa_std/proc_wait.zig").waitStatusSignal; pub const waitStatusCoreDumped = @import("sa_std/proc_wait.zig").waitStatusCoreDumped; pub const waitStatusStoppedSignal = @import("sa_std/proc_wait.zig").waitStatusStoppedSignal; pub const waitStatusContinued = @import("sa_std/proc_wait.zig").waitStatusContinued; pub const waitProcessIgnoringMissing = @import("sa_std/proc_wait.zig").waitProcessIgnoringMissing; pub const waitPidfdStatus = @import("sa_std/proc_wait.zig").waitPidfdStatus; pub const finalizeProcessExit = @import("sa_std/proc_wait.zig").finalizeProcessExit;
pub const sa_std_pidfd_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait_raw; pub const sa_std_pidfd_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait; pub const sa_std_pidfd_try_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait_raw; pub const sa_std_pidfd_try_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait;
// --- sa_std/pthread.zig ---
pub const PthreadEntryFn = @import("sa_std/pthread.zig").PthreadEntryFn; pub const PthreadTask = @import("sa_std/pthread.zig").PthreadTask; pub const PthreadHandle = @import("sa_std/pthread.zig").PthreadHandle; pub const RawPthreadOwner = @import("sa_std/pthread.zig").RawPthreadOwner; pub const RawPthreadTransfer = @import("sa_std/pthread.zig").RawPthreadTransfer; pub const pthreadToRaw = @import("sa_std/pthread.zig").pthreadToRaw; pub const rawToPthread = @import("sa_std/pthread.zig").rawToPthread; pub const pthreadTaskMain = @import("sa_std/pthread.zig").pthreadTaskMain;
pub const pthreadTaskMainC = @import("sa_std/pthread.zig").pthreadTaskMainC; pub const mapPthreadCreateError = @import("sa_std/pthread.zig").mapPthreadCreateError; pub const spawnPthread = @import("sa_std/pthread.zig").spawnPthread; pub const joinPthreadHandle = @import("sa_std/pthread.zig").joinPthreadHandle; pub const allocPthreadHandle = @import("sa_std/pthread.zig").allocPthreadHandle; pub const takePthreadHandle = @import("sa_std/pthread.zig").takePthreadHandle; pub const freePthreadHandle = @import("sa_std/pthread.zig").freePthreadHandle; pub const transferPthreadHandleToRaw = @import("sa_std/pthread.zig").transferPthreadHandleToRaw;
pub const findRawPthreadTask = @import("sa_std/pthread.zig").findRawPthreadTask; pub const removeRawPthreadOwner = @import("sa_std/pthread.zig").removeRawPthreadOwner; pub const pthread_spawn = @import("sa_std/pthread.zig").pthread_spawn; pub const pthread_spawn_detached = @import("sa_std/pthread.zig").pthread_spawn_detached; pub const pthread_join = @import("sa_std/pthread.zig").pthread_join; pub const sa_thread_as_pthread_t = @import("sa_std/pthread.zig").sa_thread_as_pthread_t; pub const sa_thread_into_pthread_t = @import("sa_std/pthread.zig").sa_thread_into_pthread_t; pub const sa_thread_raw_pthread_join = @import("sa_std/pthread.zig").sa_thread_raw_pthread_join;
pub const pthread_drop = @import("sa_std/pthread.zig").pthread_drop;
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
pub const sa_std_net_error_code_from_status = @import("sa_std/std_net.zig").sa_std_net_error_code_from_status; pub const sa_std_net_error_code_from_posix_errno = @import("sa_std/std_net.zig").sa_std_net_error_code_from_posix_errno; pub const sa_std_net_error_code_from_wsa_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_wsa_error; pub const sa_std_net_error_code_name = @import("sa_std/std_net.zig").sa_std_net_error_code_name; pub const sa_std_net_error_platform = @import("sa_std/std_net.zig").sa_std_net_error_platform; pub const sa_std_net_error_code_from_native_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_native_error; pub const sa_std_net_hostname = @import("sa_std/std_net.zig").sa_std_net_hostname; pub const sa_std_net_interface_addresses_json = @import("sa_std/std_net.zig").sa_std_net_interface_addresses_json;
pub const sa_std_net_to_socket_addr_list = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_list; pub const sa_std_net_addr_list_next = @import("sa_std/std_net.zig").sa_std_net_addr_list_next; pub const sa_std_net_addr_list_remaining = @import("sa_std/std_net.zig").sa_std_net_addr_list_remaining; pub const sa_std_net_addr_list_reset = @import("sa_std/std_net.zig").sa_std_net_addr_list_reset; pub const sa_std_net_addr_list_free = @import("sa_std/std_net.zig").sa_std_net_addr_list_free; pub const sa_std_net_addr_reverse_lookup = @import("sa_std/std_net.zig").sa_std_net_addr_reverse_lookup; pub const sa_std_net_to_socket_addr_first = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_first; pub const sa_std_net_poll_wait = @import("sa_std/std_net.zig").sa_std_net_poll_wait;
pub const sa_std_net_raw_socket = @import("sa_std/std_net.zig").sa_std_net_raw_socket; pub const sa_std_net_socket_setsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt; pub const sa_std_net_socket_getsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt; pub const sa_std_net_socket_setsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt_int; pub const sa_std_net_socket_getsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt_int; pub const sa_std_net_addr_format = @import("sa_std/std_net.zig").sa_std_net_addr_format; pub const sa_std_net_ja3_hash = @import("sa_std/std_net.zig").sa_std_net_ja3_hash; pub const sa_std_net_sha256_hex = @import("sa_std/std_net.zig").sa_std_net_sha256_hex;
pub const sa_std_net_ja4_hash12 = @import("sa_std/std_net.zig").sa_std_net_ja4_hash12;
// --- sa_std/std_net_tcp.zig ---
pub const sa_std_net_tcp_listener_set_reuseaddr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseaddr; pub const sa_std_net_tcp_listener_set_reuseport = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseport; pub const sa_std_net_tcp_listener_try_clone = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_try_clone; pub const sa_std_net_tcp_listener_set_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_only_v6; pub const sa_std_net_tcp_listener_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_only_v6; pub const sa_std_net_tcp_listener_set_nonblocking = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_nonblocking; pub const sa_std_net_tcp_listener_set_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_ttl; pub const sa_std_net_tcp_listener_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_ttl;
pub const sa_std_net_tcp_listener_take_error = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_take_error; pub const sa_std_net_tcp_listen = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listen; pub const sa_std_net_tcp_accept = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept; pub const sa_std_net_tcp_accept_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept_addr; pub const sa_std_net_tcp_listener_local_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_local_addr; pub const sa_std_net_tcp_listener_from_raw_fd = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_from_raw_fd; pub const sa_std_net_tcp_connect = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect; pub const sa_std_net_tcp_connect_timeout = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout;
pub const sa_std_net_tcp_connect_timeout_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_addr; pub const sa_std_net_tcp_connect_timeout_all = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_all;
// --- sa_std/std_net_tcp_stream.zig ---
pub const sa_std_net_tcp_stream_read = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read; pub const sa_std_net_tcp_stream_read_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_vectored; pub const sa_std_net_tcp_stream_write_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_vectored; pub const sa_std_net_tcp_stream_peek = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peek; pub const sa_std_net_tcp_stream_write = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write; pub const sa_std_net_tcp_stream_peer_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peer_addr; pub const sa_std_net_tcp_stream_local_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_local_addr; pub const sa_std_net_tcp_stream_try_clone = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_try_clone;
pub const sa_std_net_tcp_stream_set_nonblocking = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nonblocking; pub const sa_std_net_tcp_stream_set_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nodelay; pub const sa_std_net_tcp_stream_set_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_linger; pub const sa_std_net_tcp_stream_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_linger; pub const sa_std_net_tcp_stream_set_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_quickack; pub const sa_std_net_tcp_stream_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_quickack; pub const sa_std_net_tcp_stream_set_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_deferaccept; pub const sa_std_net_tcp_stream_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_deferaccept;
pub const sa_std_net_tcp_stream_set_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive; pub const sa_std_net_tcp_stream_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_keepalive; pub const sa_std_net_tcp_stream_set_keepalive_params = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive_params; pub const sa_std_net_tcp_stream_set_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_read_timeout; pub const sa_std_net_tcp_stream_set_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_write_timeout; pub const sa_std_net_tcp_stream_set_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_ttl; pub const sa_std_net_tcp_stream_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_timeout; pub const sa_std_net_tcp_stream_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_timeout;
pub const sa_std_net_tcp_stream_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_nodelay; pub const sa_std_net_tcp_stream_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_ttl; pub const sa_std_net_tcp_stream_set_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_recv_buffer_size; pub const sa_std_net_tcp_stream_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_recv_buffer_size; pub const sa_std_net_tcp_stream_set_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_send_buffer_size; pub const sa_std_net_tcp_stream_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_buffer_size; pub const sa_std_net_tcp_stream_take_error = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_take_error; pub const sa_std_net_tcp_stream_send_file = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_file;
pub const sa_std_net_tcp_stream_from_raw_fd = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_from_raw_fd;
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
// --- sa_std/time.zig ---
pub const sa_time_instant_ns = @import("sa_std/time.zig").sa_time_instant_ns; pub const sa_time_unix_s = @import("sa_std/time.zig").sa_time_unix_s; pub const sa_time_unix_ms = @import("sa_std/time.zig").sa_time_unix_ms; pub const sa_time_iso_from_unix_ms = @import("sa_std/time.zig").sa_time_iso_from_unix_ms; pub const sa_time_parse_iso = @import("sa_std/time.zig").sa_time_parse_iso; pub const sa_time_get_full_year = @import("sa_std/time.zig").sa_time_get_full_year; pub const sa_time_get_month = @import("sa_std/time.zig").sa_time_get_month; pub const sa_time_get_date = @import("sa_std/time.zig").sa_time_get_date;
pub const sa_time_get_hours = @import("sa_std/time.zig").sa_time_get_hours; pub const sa_time_get_minutes = @import("sa_std/time.zig").sa_time_get_minutes; pub const sa_time_get_seconds = @import("sa_std/time.zig").sa_time_get_seconds; pub const sa_time_get_milliseconds = @import("sa_std/time.zig").sa_time_get_milliseconds; pub const sa_time_get_day = @import("sa_std/time.zig").sa_time_get_day; pub const sa_time_format_utc = @import("sa_std/time.zig").sa_time_format_utc; pub const sa_time_set_field = @import("sa_std/time.zig").sa_time_set_field; pub const sa_time_unix_ns = @import("sa_std/time.zig").sa_time_unix_ns;
pub const sa_time_utc_now = @import("sa_std/time.zig").sa_time_utc_now; pub const sa_time_sleep_ns = @import("sa_std/time.zig").sa_time_sleep_ns; pub const sa_time_sleep_ms = @import("sa_std/time.zig").sa_time_sleep_ms;


/// Runtime permission gate (sala 16_policy): checked at resource
/// acquisition points only. No context installed -> allowed (the
/// host surface enforces "no policy, no start"). Denial returns the
/// dedicated SA_STD_ERR_PERMISSION_DENIED status; getters without a
/// status channel (env, time, random) deny by returning zero, and
/// every denial is audit-logged through the installed sink.
pub fn policyAllows(resource: sa_policy.Resource) bool {
    // On wasm there is no ELF-constructor guarantee, so the first gated
    // call installs the policy lazily (policyBootstrap is idempotent).
    if (comptime is_wasm) policyBootstrap();
    if (sa_policy.active_context == null) return true;
    const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
    return sa_policy.gate(std.heap.page_allocator, resource, now_ns);
}

/// Run-category policy check shared with satellite runtime files
/// (sa_pty.zig): a PTY spawn acquires a process exactly like the spawn
/// funnel above, so it goes through the same 16_policy gate.
pub fn saStdPolicyAllowsRun(program: []const u8) bool {
    return policyAllows(.{ .run = program });
}

/// Fs-read policy check shared with satellite runtime files
/// (sa_fs_watch.zig): registering a watch is a read-side acquisition.
pub fn saStdPolicyAllowsFsRead(path: []const u8) bool {
    return policyAllows(.{ .fs = .{ .path = path, .write = false } });
}

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




pub fn policyEnvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return sio.getEnvVarOwned(allocator, name) catch null;
}




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


// wasm32-wasi compat (stage1: archive must compile; sockets/process/dlopen
// stubbed to UNSUPPORTED): SockAddrT/W/SIG are `void` on wasi, and
// std.os.linux has no wasm syscalls. Provide minimal layout-compatible
// aliases so signatures type-check; bodies return UNSUPPORTED via
// `if (comptime is_wasm)` guards.
pub const is_wasm = builtin.cpu.arch.isWasm();
pub const is_linux = builtin.os.tag == .linux;
const WasiSockAddrUn = extern struct { family: u16 = 0, path: [108]u8 = undefined };
const WasiSockAddrIn = extern struct { port: u16 = 0, addr: u32 = 0, zero: [8]u8 = undefined };
const WasiSockAddrIn6 = extern struct { port: u16 = 0, flowinfo: u32 = 0, addr: [16]u8 = undefined, scope_id: u32 = 0 };
const WasiSockAddrStorage = extern struct { family: u16 = 0, __pad: [126]u8 = undefined };
const WasiSockAddr = extern struct { family: u16 = 0, data: [14]u8 = undefined };
pub const SockAddrUnT = if (is_wasm) WasiSockAddrUn else std.posix.sockaddr.un;
const SockAddrInT = if (is_wasm) WasiSockAddrIn else std.posix.sockaddr.in;
const SockAddrIn6T = if (is_wasm) WasiSockAddrIn6 else std.posix.sockaddr.in6;
pub const SockAddrStorageT = if (is_wasm) WasiSockAddrStorage else std.posix.sockaddr.storage;
pub const SockAddrT = if (is_wasm) WasiSockAddr else std.posix.sockaddr;
pub const SockLenT = if (is_wasm) u32 else std.posix.socklen_t;
// wasi has no wait macros/signals (std.posix.W/SIG are void); dummies so
// status helpers type-check (callers stubbed to UNSUPPORTED on wasm).
// wasi-libc has no AF/SOL (void via std.c); Linux-value dummies for compile.
const WasiAF = struct {
    pub const UNIX: u16 = 1;
    pub const INET: u16 = 2;
    pub const INET6: u16 = 10;
};
pub const AFT = if (is_wasm) WasiAF else std.posix.AF;
const WasiSOL = struct {
    pub const SOCKET: u32 = 1;
};
pub const SOLT = if (is_wasm) WasiSOL else std.posix.SOL;
const WasiSO = struct {
    pub const REUSEADDR: u32 = 2;
    pub const TYPE: u32 = 3;
    pub const ERROR: u32 = 4;
    pub const BROADCAST: u32 = 6;
    pub const SNDBUF: u32 = 7;
    pub const RCVBUF: u32 = 8;
    pub const KEEPALIVE: u32 = 9;
    pub const LINGER: u32 = 13;
    pub const REUSEPORT: u32 = 15;
    pub const PEERCRED: u32 = 17;
    pub const RCVTIMEO: u32 = 20;
    pub const SNDTIMEO: u32 = 21;
    pub const ACCEPTCONN: u32 = 30;
};
pub const SOT = if (is_wasm) WasiSO else std.posix.SO;
const WasiIPPROTO = struct {
    pub const IP: u32 = 0;
    pub const TCP: u32 = 6;
    pub const UDP: u32 = 17;
    pub const IPV6: u32 = 41;
};
pub const IPPROTOT = if (is_wasm) WasiIPPROTO else std.posix.IPPROTO;
const WasiSOCK = struct {
    pub const STREAM: u32 = 1;
    pub const DGRAM: u32 = 2;
    pub const NONBLOCK: u32 = 2048;
    pub const CLOEXEC: u32 = 524288;
};
pub const SOCKT = if (is_wasm) WasiSOCK else std.posix.SOCK;
// Linux-only socket options/constants fall back to neutral values elsewhere;
// the export functions that use them are compiled out of non-Linux builds.
pub const TCP_QUICKACK: u32 = if (is_linux) std.os.linux.TCP.QUICKACK else 0;
pub const TCP_DEFER_ACCEPT: u32 = if (is_linux) std.os.linux.TCP.DEFER_ACCEPT else 0;
pub const TCP_KEEPIDLE: u32 = if (is_linux) std.os.linux.TCP.KEEPIDLE else if (builtin.os.tag == .freebsd) 256 else std.posix.TCP.KEEPALIVE;
pub const TCP_KEEPINTVL: u32 = if (is_linux) std.os.linux.TCP.KEEPINTVL else std.posix.TCP.KEEPINTVL;
pub const TCP_KEEPCNT: u32 = if (is_linux) std.os.linux.TCP.KEEPCNT else std.posix.TCP.KEEPCNT;
pub const SO_PASSCRED: u32 = if (is_linux) std.os.linux.SO.PASSCRED else 0;
pub const SO_MARK: u32 = if (is_linux) std.os.linux.SO.MARK else 0;
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
    // force-emit all fns of sa_cookie.zig (43 fns, loop over decls)
    {
        const m = @import("sa_cookie.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_crypto.zig (27 fns, loop over decls)
    {
        const m = @import("sa_crypto.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_crypto_asym.zig (17 fns, loop over decls)
    {
        const m = @import("sa_crypto_asym.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_fs_watch.zig (6 fns, loop over decls)
    {
        const m = @import("sa_fs_watch.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_http_client.zig (6 fns, loop over decls)
    {
        const m = @import("sa_http_client.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_http_server.zig (48 fns, loop over decls)
    {
        const m = @import("sa_http_server.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_mysql_client.zig (30 fns, loop over decls)
    {
        const m = @import("sa_mysql_client.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_pg.zig (4 fns, loop over decls)
    {
        const m = @import("sa_pg.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_pty.zig (10 fns, loop over decls)
    {
        const m = @import("sa_pty.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_quic.zig (3 fns, loop over decls)
    {
        const m = @import("sa_quic.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/deno.zig (37 fns, loop over decls)
    {
        const m = @import("sa_std/deno.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/env.zig (22 fns, loop over decls)
    {
        const m = @import("sa_std/env.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/fmt.zig (14 fns, loop over decls)
    {
        const m = @import("sa_std/fmt.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/fs.zig (55 fns, loop over decls)
    {
        const m = @import("sa_std/fs.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/fs_meta.zig (39 fns, loop over decls)
    {
        const m = @import("sa_std/fs_meta.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/io.zig (13 fns, loop over decls)
    {
        const m = @import("sa_std/io.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/json_io.zig (31 fns, loop over decls)
    {
        const m = @import("sa_std/json_io.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/math.zig (7 fns, loop over decls)
    {
        const m = @import("sa_std/math.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/net.zig (61 fns, loop over decls)
    {
        const m = @import("sa_std/net.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/regex.zig (22 fns, loop over decls)
    {
        const m = @import("sa_std/regex.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_fs.zig (27 fns, loop over decls)
    {
        const m = @import("sa_std/std_fs.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net.zig (25 fns, loop over decls)
    {
        const m = @import("sa_std/std_net.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_tcp.zig (18 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_tcp.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_tcp_stream.zig (33 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_tcp_stream.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_udp.zig (21 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_udp.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_udp_io.zig (15 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_udp_io.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_udp_set.zig (14 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_udp_set.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_unix.zig (20 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_unix.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_net_unix_dgram.zig (19 fns, loop over decls)
    {
        const m = @import("sa_std/std_net_unix_dgram.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_process.zig (35 fns, loop over decls)
    {
        const m = @import("sa_std/std_process.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/std_process_spawn.zig (15 fns, loop over decls)
    {
        const m = @import("sa_std/std_process_spawn.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/str.zig (10 fns, loop over decls)
    {
        const m = @import("sa_std/str.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/string.zig (14 fns, loop over decls)
    {
        const m = @import("sa_std/string.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/term.zig (7 fns, loop over decls)
    {
        const m = @import("sa_std/term.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/time.zig (19 fns, loop over decls)
    {
        const m = @import("sa_std/time.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tls_client.zig (11 fns, loop over decls)
    {
        const m = @import("sa_tls_client.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tls_server.zig (8 fns, loop over decls)
    {
        const m = @import("sa_tls_server.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tls_shaped.zig (4 fns, loop over decls)
    {
        const m = @import("sa_tls_shaped.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_toml.zig (29 fns, loop over decls)
    {
        const m = @import("sa_toml.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_tree_sitter.zig (34 fns, loop over decls)
    {
        const m = @import("sa_tree_sitter.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_yaml.zig (31 fns, loop over decls)
    {
        const m = @import("sa_yaml.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    // force-emit all fns of sa_std/b64_simd.zig (loop over decls)
    {
        const m = @import("sa_std/b64_simd.zig");
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
    // force-emit all fns of sa_std/json.zig (loop over decls)
    {
        const m = @import("sa_std/json.zig");
        for (std.meta.declarations(m)) |decl_name| {
            _ = &@field(m, decl_name);
        }
    }
    if (builtin.os.tag == .linux) {
        _ = &@import("sa_net_uring.zig").sa_netx_init;
    }
}

pub const RegexC = if (is_wasm) extern struct {
    re_nsub: usize,
    __opaque: ?*anyopaque,
    __padding: [4]?*anyopaque,
    __nsub2: usize,
    __padding2: u8,
} else extern struct {
    buffer: ?*anyopaque,
    allocated: c_ulong,
    used: c_ulong,
    syntax: c_ulong,
    fastmap: ?[*]u8,
    translate: ?[*]u8,
    re_nsub: usize,
    flags: u32,
};

pub const RegexMatchC = extern struct {
    rm_so: c_int,
    rm_eo: c_int,
};

extern fn regcomp(preg: ?*RegexC, pattern: [*c]const u8, cflags: c_int) c_int;
extern fn regexec(preg: ?*const RegexC, text: [*c]const u8, nmatch: usize, pmatch: [*]RegexMatchC, eflags: c_int) c_int;
extern fn regfree(preg: ?*RegexC) void;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

const InAddrC = extern struct {
    s_addr: u32,
};

const IpMreqC = extern struct {
    imr_multiaddr: InAddrC,
    imr_interface: InAddrC,
};

const Ipv6MreqC = extern struct {
    ipv6mr_multiaddr: [16]u8,
    ipv6mr_interface: u32,
};

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



// --- Cross-platform compat: Linux-first, macOS via conditionals ---
// waitid/pidfd flags are Linux-only; 0 elsewhere (pidfd path is Linux-only).
// MSG_PEEK: std.posix.MSG is Linux-only in zig 0.14; Darwin value is 0x2.
// TCP_NODELAY == 1 on Linux, macOS and FreeBSD. Spell it out: std.posix.TCP
// is void on FreeBSD in zig 0.14, and std.os.linux.TCP.* are Linux values.
pub const tcp_nodelay: u32 = 1;
// --- FreeBSD compat (zig 0.14 std leaves several POSIX surfaces
// unimplemented for freebsd: uname, TCP consts, if_nametoindex) ---
const fbsd_sys_nmln: usize = 256;
pub const fbsd_utsname = extern struct {
    sysname: [fbsd_sys_nmln]u8,
    nodename: [fbsd_sys_nmln]u8,
    release: [fbsd_sys_nmln]u8,
    version: [fbsd_sys_nmln]u8,
    machine: [fbsd_sys_nmln]u8,
};
extern fn uname(buf: *fbsd_utsname) c_int;
extern fn if_nametoindex(ifname: [*:0]const u8) c_uint;
// Non-Linux targets call libc recvmsg directly. Note: the extern name must be
// exactly "recvmsg" — macOS dylibs reject undefined symbols, unlike ELF .so.
extern "c" fn recvmsg(sockfd: std.posix.fd_t, msg: *MsghdrT, flags: c_int) isize;
extern "c" fn __error() *c_int;

// Mirrors C sa_net_iov in sa_std.h. Layout must stay { u8* base; usize len; }.

/// Cap on iovec entries accepted per vectored call. Matches POSIX IOV_MAX where
/// available and stays comfortably below common OS hard limits.



pub const IP_MULTICAST_TTL_OPT: u32 = 33;
pub const IP_MULTICAST_LOOP_OPT: u32 = 34;
pub const IP_MULTICAST_IF_OPT: u32 = 32;
pub const IP_ADD_MEMBERSHIP_OPT: u32 = 35;
pub const IP_DROP_MEMBERSHIP_OPT: u32 = 36;
pub const IPV6_JOIN_GROUP_OPT: u32 = 20;
pub const IPV6_LEAVE_GROUP_OPT: u32 = 21;
pub const IPV6_MULTICAST_HOPS_OPT: u32 = 18;
pub const IPV6_MULTICAST_LOOP_OPT: u32 = 19;
pub const IPV6_MULTICAST_IF_OPT: u32 = 17;

pub const SA_PLUGIN_DESCRIPTOR_SYMBOL: [:0]const u8 = "saasm_plugin_descriptor_v1";



pub const SaPluginDescriptor = extern struct {
    abi_version: u32,
    descriptor_size: u32,
    name: [*:0]const u8,
};




// eflags slot value for regexec: restrict the search to the pmatch[0] range
// while reporting absolute offsets. glibc assigns it the same numeric value
// as the SA_REGEX_NEWLINE *cflag*; the two live in different parameters.

pub const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

pub const SaJsonStringifyOptions = extern struct {
    whitespace: u32 = SA_JSON_WHITESPACE_MINIFIED,
    emit_null_optional_fields: u8 = 1,
    emit_strings_as_arrays: u8 = 0,
    escape_unicode: u8 = 0,
    emit_nonportable_numbers_as_strings: u8 = 0,
};

const DEFAULT_CAPTURE_LIMIT: usize = 50 * 1024;

const empty_bytes: [0]u8 = .{};
const empty_mut_bytes: [0]u8 = .{};

const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *BufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};




const DirEntryHandle = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    kind: u32,
    ino: u64,

    pub fn deinit(self: *DirEntryHandle) void {
        if (self.name.len != 0) self.allocator.free(self.name);
        self.name = &.{};
    }
};

pub const NetAddrHandle = struct {
    allocator: std.mem.Allocator,
    host: []u8,
    addr: NetAddress,

    pub fn deinit(self: *NetAddrHandle) void {
        if (self.host.len != 0) self.allocator.free(self.host);
        self.host = &.{};
    }

    pub fn init(allocator: std.mem.Allocator, address: NetAddress) !NetAddrHandle {
        const host = try addressHostText(allocator, address);
        return .{
            .allocator = allocator,
            .host = host,
            .addr = address,
        };
    }
};

const NetAddrListHandle = struct {
    allocator: std.mem.Allocator,
    addresses: []NetAddress,
    next_index: usize = 0,

    pub fn deinit(self: *NetAddrListHandle) void {
        if (self.addresses.len != 0) self.allocator.free(self.addresses);
        self.addresses = &.{};
        self.next_index = 0;
    }
};






pub fn registerNetAddrList(host: []const u8, port: u16) !u64 {
    var list = try netGetAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
    const addresses = try std.heap.page_allocator.dupe(NetAddress, list.addrs);
    errdefer std.heap.page_allocator.free(addresses);
    return registerResource(.{ .net_addr_list = .{
        .allocator = std.heap.page_allocator,
        .addresses = addresses,
    } });
}
pub fn registerNetAddrOutLocked(address: NetAddress, out_handle: *u64) i32 {
    var net_addr = NetAddrHandle.init(std.heap.page_allocator, address) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
        net_addr.deinit();
        return finishErr(err);
    };
    out_handle.* = handle;
    return finish(SA_STD_OK);
}

fn addressHostText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET => blk: {
            const sin: *const SockAddrInT = @ptrCast(@alignCast(&address.storage));
            const ip: [4]u8 = @bitCast(sin.addr);
            break :blk try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        },
        AFT.INET6 => blk: {
            const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&address.storage));
            var segbuf: [8]u16 = undefined;
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                segbuf[i] = std.mem.readInt(u16, sin6.addr[i * 2 ..][0..2], .big);
            }
            var outbuf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&outbuf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
                segbuf[0], segbuf[1], segbuf[2], segbuf[3], segbuf[4], segbuf[5], segbuf[6], segbuf[7],
            });
            if (sin6.scope_id != 0) {
                const with_scope = try std.fmt.allocPrint(allocator, "{s}%{d}", .{ text, sin6.scope_id });
                break :blk with_scope;
            }
            break :blk try allocator.dupe(u8, text);
        },
        AFT.UNIX => try allocator.dupe(u8, address.unixPath()),
        else => try allocator.dupe(u8, ""),
    };
}

pub fn addressSocketText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET, AFT.INET6 => blk: {
            const host = try addressHostText(allocator, address);
            defer allocator.free(host);
            if (address.storage.family == AFT.INET6) {
                break :blk try std.fmt.allocPrint(allocator, "[{s}]:{d}", .{ host, address.getPort() });
            }
            break :blk try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, address.getPort() });
        },
        else => try addressHostText(allocator, address),
    };
}

const FmtHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *FmtHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};


// A JSON node handle addresses a value inside its document tree by PATH
// (object keys / array indices from the document root). Every acquire
// re-resolves the path against the live tree, so a mutation performed
// through any handle is visible through all other handles of the same
// document. Removing the exact key a handle points at (or an ancestor of
// it) detaches the handle: later operations fail with InvalidHandle
// instead of reading a stale snapshot.


// Returns a fully-owned copy of `base` with `segment` appended (key bytes
// duplicated with `allocator`).


pub const JsonBufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *JsonBufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};



pub const JsonWriterHandle = struct {
    allocator: std.mem.Allocator,
    aw: std.Io.Writer.Allocating,
    stream: std.json.Stringify,
    options: std.json.Stringify.Options,
    root_value_started: bool = false,
    root_value_complete: bool = false,
    open_depth: u32 = 0,
    result_buffer: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator, options: std.json.Stringify.Options) !*JsonWriterHandle {
        const handle = try allocator.create(JsonWriterHandle);
        handle.* = .{
            .allocator = allocator,
            .aw = .init(allocator),
            .stream = undefined,
            .options = options,
            .root_value_started = false,
            .root_value_complete = false,
            .open_depth = 0,
            .result_buffer = null,
        };
        handle.stream = .{ .writer = &handle.aw.writer, .options = options };
        return handle;
    }

    pub fn deinit(self: *JsonWriterHandle) void {
        self.aw.deinit();
        self.allocator.destroy(self);
    }
};

pub const RegexHandle = struct {
    allocator: std.mem.Allocator,
    pattern_z: []u8,
    compiled: RegexC,
    compiled_valid: bool = false,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, cflags: c_int) !*RegexHandle {
        if (std.mem.indexOfScalar(u8, pattern, 0) != null) return error.InvalidArgument;
        const owned_pattern = try allocator.alloc(u8, pattern.len + 1);
        errdefer allocator.free(owned_pattern);
        @memcpy(owned_pattern[0..pattern.len], pattern);
        owned_pattern[pattern.len] = 0;
        const handle = try allocator.create(RegexHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .pattern_z = owned_pattern,
            .compiled = undefined,
            .compiled_valid = false,
        };
        const pattern_c: [*:0]const u8 = @ptrCast(owned_pattern.ptr);
        const rc = regcomp(&handle.compiled, pattern_c, cflags);
        if (rc != SA_REGEX_REG_NOERROR) {
            return regexErrorToZig(rc);
        }
        handle.compiled_valid = true;
        return handle;
    }

    pub fn deinit(self: *RegexHandle) void {
        if (self.compiled_valid) regfree(&self.compiled);
        if (self.pattern_z.len != 0) self.allocator.free(self.pattern_z);
        self.pattern_z = &.{};
        self.compiled_valid = false;
    }

    pub fn destroy(self: *RegexHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};








// Copies text into an owned NUL-terminated buffer, rejecting embedded NUL
// bytes exactly like regexMatchHandle does.

// Runs regexec over the byte range [start, end) of an owned NUL-terminated
// text using REG_STARTEND, so reported offsets stay absolute and `^` / `$`
// keep whole-text semantics. Returns the raw regcomp-family status code.

// Collects every non-overlapping match in text_z (an owned NUL-terminated
// copy), in left-to-right order. After an empty match the search advances
// one byte — the byte-level form of the JS global-exec loop (JS advances
// one code point; this engine is byte-oriented). Caller owns the returned
// outer slice and every inner groups slice.


// Appends the JS-style substitution of `replacement` for one match:
// $$ is a literal $, $& the whole match, $` the text before the match,
// $' the text after it, and $n / $nn capture groups (a group that did not
// participate expands to nothing; an out-of-range $n stays literal).
// $<name> passes through literally: POSIX ERE has no named groups.

// Builds the replaced text. With `global` false only the first match is
// replaced (JS String.replace without /g); with true every match from the
// global iteration is replaced (JS /g and replaceAll). The result is an
// owned slice; when nothing matches it is a copy of the input text.

// Builds the piece list for JS String.split semantics over text_z. Pieces
// are (start, end) ranges into text_z; non-participating capture groups
// keep rm_so < 0. `limit` caps the TOTAL piece count (groups included);
// limit == 0 means no limit in this API (JS limit 0 returns [] — a
// deliberate divergence, documented in regex.sai).

pub fn jsonKindOf(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}


pub fn jsonValueAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| {
            if (!std.math.isFinite(inner)) return error.InvalidArgument;
            return inner;
        },
        .number_string => |text| blk: {
            const parsed = std.fmt.parseFloat(f64, text) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) break :blk error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner)) break :blk error.InvalidArgument;
            if (@round(inner) != inner) break :blk error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk error.InvalidArgument;
            if (inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
            error.Overflow, error.InvalidCharacter => return error.InvalidArgument,
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}



// Walks `path` from the document root and returns a pointer to the live
// tree value. The pointer is only valid until the next tree mutation.








// Deep-copies a JSON value into `allocator` (the target document's arena),
// duplicating every string, array and object so the copy shares no storage
// with the source tree.
pub fn jsonValueClone(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |inner| .{ .bool = inner },
        .integer => |inner| .{ .integer = inner },
        .float => |inner| .{ .float = inner },
        .number_string => |text| .{ .number_string = try allocator.dupe(u8, text) },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |array| blk: {
            var cloned = std.json.Array.init(allocator);
            errdefer cloned.deinit();
            for (array.items) |item| {
                try cloned.append(try jsonValueClone(allocator, item));
            }
            break :blk .{ .array = cloned };
        },
        .object => |object| blk: {
            var cloned: std.json.ObjectMap = .empty;
            var it = object.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.put(allocator, key_copy, try jsonValueClone(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = cloned };
        },
    };
}


// Resolves the handle's slot under the registry lock for an in-place tree
// mutation. The caller must hold no other registry acquisition.




pub fn acquireJsonWriterForWrite(writer: u64) !*JsonWriterHandle {
    const resource = getResourceLocked(writer) orelse return error.InvalidHandle;
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return error.InvalidHandle,
    };
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return error.InvalidArgument;
    return writer_handle;
}

pub fn markJsonWriterValueComplete(writer_handle: *JsonWriterHandle) void {
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
}

pub fn jsonWriterObjectFieldLocked(writer_handle: *JsonWriterHandle, key: []const u8) !void {
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.open_depth == 0) return error.InvalidArgument;
    try writer_handle.stream.objectField(key);
}

pub fn tokenTypeOf(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

pub fn tokenTextSlice(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number => |slice| slice,
        .partial_number => |slice| slice,
        .string => |slice| slice,
        .partial_string => |slice| slice,
        else => null,
    };
}



const EnvHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *EnvHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

const SaNetAddr = extern struct {
    family: u32,
    port: u32,
    host_ptr: [*]u8,
    host_len: u64,
    scope_id: u64,
};

pub const Timeval = std.posix.timeval;
const LingerOption = extern struct { onoff: i32, linger: i32 };
pub const Timespec = std.posix.timespec;
const TimespecSec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).sec);
const TimespecNsec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).nsec);

const OwnedFdHandle = struct {
    fd: std.posix.fd_t,

    fn deinit(self: *OwnedFdHandle) void {
        lxClose(self.fd);
        self.fd = -1;
    }
};

const TerminalSession = struct {
    fd: std.posix.fd_t,
    saved: std.posix.termios,

    fn deinit(self: *TerminalSession) !void {
        try std.posix.tcsetattr(self.fd, .FLUSH, self.saved);
    }
};

pub const SaProcessArgv = extern struct {
    data: [*]const u8,
    len: u64,
};

pub const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};


pub const TcpListener = struct {
    fd: std.posix.fd_t,
    addr: NetAddress,
};

pub const Resource = union(enum) {
    file: sio.File,
    dynamic_lib: *DynamicLibHandle,
    tcp_stream: std.posix.fd_t,
    tcp_listener: TcpListener,
    udp_socket: std.posix.socket_t,
    buffer: BufferHandle,
    metadata: MetadataHandle,
    dir_entries: DirEntriesHandle,
    dir_entry: DirEntryHandle,
    net_addr: NetAddrHandle,
    net_addr_list: NetAddrListHandle,
    unix_addr: UnixAddrHandle,
    fmt: FmtHandle,
    env: EnvHandle,
    json_node: JsonNodeHandle,
    json_buffer: JsonBufferHandle,
    json_scanner: *JsonScannerHandle,
    json_stream: *JsonStreamHandle,
    json_writer: *JsonWriterHandle,
    regex: *RegexHandle,
    regex_match: *RegexMatchHandle,
    regex_match_list: *RegexMatchListHandle,
    regex_split_list: *RegexSplitListHandle,
    regex_buffer: *RegexBufferHandle,
    owned_fd: OwnedFdHandle,
    terminal_session: TerminalSession,
    process: ProcessHandle,

    pub fn close(self: *Resource) !void {
        switch (self.*) {
            .file => |file| file.close(),
            .dynamic_lib => |handle| {
                handle.deinit();
                std.heap.page_allocator.destroy(handle);
            },
            .tcp_stream => |stream| lxClose(stream),
            .tcp_listener => |*server| lxClose(server.fd),
            .udp_socket => |fd| lxClose(fd),
            .buffer => |*buffer| buffer.deinit(),
            .metadata => |*metadata| metadata.deinit(),
            .dir_entries => |*entries| entries.deinit(),
            .dir_entry => |*entry| entry.deinit(),
            .net_addr => |*addr| addr.deinit(),
            .net_addr_list => |*list| list.deinit(),
            .unix_addr => |*addr| addr.deinit(),
            .fmt => |*fmt| fmt.deinit(),
            .env => |*env| env.deinit(),
            .json_node => |*node| node.deinit(),
            .json_buffer => |*buffer| buffer.deinit(),
            .json_scanner => |scanner| scanner.destroy(),
            .json_stream => |stream| stream.deinit(),
            .json_writer => |writer| writer.deinit(),
            .regex => |regex| regex.destroy(),
            .regex_match => |match| match.destroy(),
            .regex_match_list => |list| list.destroy(),
            .regex_split_list => |list| list.destroy(),
            .regex_buffer => |buffer| buffer.destroy(),
            .owned_fd => |*fd| fd.deinit(),
            .terminal_session => |*session| {
                // No terminal sessions can exist on WASI (raw_enter stubbed);
                // skip the tcsetattr restore, which wasi-libc does not provide.
                if (is_wasm) {} else try session.deinit();
            },
            .process => |*proc| proc.deinit(),
        }
        self.* = undefined;
    }
};

pub var registry_mutex: std.atomic.Mutex = .unlocked;
pub threadlocal var last_error: i32 = SA_STD_OK;
var compatibility_mmap_page: [4096]u8 = std.mem.zeroes([4096]u8);
var compatibility_dlsym_cookie: [1]u8 = .{0};



extern fn sa_host_pthread_create(thread: *std.c.pthread_t, attr: ?*const std.c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_join(thread: std.c.pthread_t, retval: ?*?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_detach(thread: std.c.pthread_t) callconv(.c) c_int;



















pub fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

pub fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.PathAlreadyExists => SA_STD_ERR_ALREADY_EXISTS,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.WouldBlock => SA_STD_ERR_IO,
        error.NotATerminal, error.ProcessOrphaned => SA_STD_ERR_UNSUPPORTED,
        error.FileDescriptorAlreadyPresentInSet, error.OperationCausesCircularLoop => SA_STD_ERR_INVALID_ARGUMENT,
        error.FileDescriptorNotRegistered => SA_STD_ERR_INVALID_HANDLE,
        error.FileDescriptorIncompatibleWithEpoll => SA_STD_ERR_UNSUPPORTED,
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.UnexpectedToken,
        error.InvalidNumber,
        error.DuplicateField,
        error.UnknownField,
        error.MissingField,
        error.LengthMismatch,
        error.InvalidEnumTag,
        error.ValueTooLong,
        error.BufferUnderrun,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.PolicyDenied => SA_STD_ERR_PERMISSION_DENIED,
        error.AlreadyConnected,
        error.ConnectionPending,
        error.SocketNotConnected,
        error.UnreachableAddress,
        error.NetworkSubsystemFailed,
        => SA_STD_ERR_NET,
        error.MessageTooBig, error.NoSpaceLeft => SA_STD_ERR_TRUNCATED,
        error.Unsupported, error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => SA_STD_ERR_UNSUPPORTED,
        error.ProcessNotFound, error.AlreadyTerminated => SA_STD_ERR_INVALID_HANDLE,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NotDir,
        error.IsDir,
        error.InvalidIPAddressFormat,
        error.InvalidCharacter,
        error.InvalidEnd,
        error.Incomplete,
        error.NonCanonical,
        error.InvalidIpv4Mapping,
        error.Overflow,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.RegexInvalidArgument,
        error.RegexNoMatch,
        error.RegexBadPattern,
        error.RegexOutOfMemory,
        error.UnknownHostName,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.NetworkUnreachable,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.AddressInUse,
        error.AddressNotAvailable,
        error.HostLacksNetworkAddresses,
        error.ServiceUnavailable,
        => SA_STD_ERR_NET,
        else => SA_STD_ERR_IO,
    };
}

pub fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

pub fn fillUtcNow(out: *TimeDate) !void {
    const now_ts = std.Io.Clock.real.now(sio.io());
    const unix_ms = now_ts.toMilliseconds();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = now_ts.toNanoseconds();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @backingInt(month_day.month),
        .day = @as(u8, @intCast(month_day.day_index + 1)),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))),
    };
}

pub fn monotonicNowNs() !u64 {
    // Raw monotonic-clock reading (ns since boot), the same contract
    // sa_time_unix_ns already uses for the wall clock: callers diff two
    // readings, and a reading of 0 is reserved for policy denial or
    // clock failure. (The previous origin-relative form returned
    // exactly 0 to the first caller in every process, which read as a
    // dead clock on every surface exposing the raw value:
    // Instant::now().raw_ns(), timer_now_ns, sched_now_ns.)
    const now_ns: i128 = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (now_ns <= 0) return 0;
    if (now_ns > std.math.maxInt(u64)) return std.math.maxInt(u64);
    return @intCast(now_ns);
}

pub fn lenAsUsize(len: u64) !usize {
    if (len > @as(u64, @intCast(std.math.maxInt(usize)))) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

pub fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}


pub fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return empty_mut_bytes[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}






pub fn setSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = if (enabled) 1 else 0;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&value));
}

pub fn setSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32, value: i32) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32, value: u32) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}


pub fn setSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32, value: u8) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, bytes: []const u8) !void {
    try std.posix.setsockopt(fd, level, optname, bytes);
}

fn lingerSeconds(timeout_ns: u64) !i32 {
    const seconds = timeout_ns / std.time.ns_per_s;
    return std.math.cast(i32, seconds) orelse error.InvalidArgument;
}

pub fn setSocketOptLinger(fd: std.posix.fd_t, enabled: bool, timeout_ns: u64) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    const seconds = if (enabled) try lingerSeconds(timeout_ns) else 0;
    var value = LingerOption{ .onoff = if (enabled) 1 else 0, .linger = seconds };
    try std.posix.setsockopt(fd, SOLT.SOCKET, SOT.LINGER, std.mem.asBytes(&value));
}

pub fn getSocketOptLinger(fd: std.posix.fd_t) !LingerOption {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value = LingerOption{ .onoff = 0, .linger = 0 };
    var len: SockLenT = @sizeOf(LingerOption);
    const rc = std.os.linux.getsockopt(fd, SOLT.SOCKET, SOT.LINGER, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(LingerOption)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}


// DEF-NET-V6-DTLS (D1): raw setsockopt that surfaces kernel refusals as
// errors. std.posix.setsockopt maps EINVAL/BADF/NOTSOCK to `unreachable`,
// which aborts the whole process for a legitimate refusal -- notably
// IPV6_V6ONLY on an already-bound socket, which the kernel only accepts
// before bind. Callers that can honour the option another way need the
// errno, not a trap.

// IPV6_V6ONLY is a bind-time option: once a socket is bound the kernel
// refuses to change it (EINVAL). Every socket behind a registry handle
// is already bound, so honour a post-bind change by rebuilding the
// socket with the option applied before bind and swapping the fd in
// the registry resource. Queued datagrams / pending connections on the
// old socket are dropped -- the unavoidable price of changing a
// bind-time option after bind. On a bind failure the pre-change socket
// shape is restored best-effort so a failed change does not silently
// destroy a working handle.


pub const LinuxUCred = extern struct {
    pid: i32,
    uid: u32,
    gid: u32,
};


// W1-DEF-UNIX-DGRAM-PEERCRED-ZERO: for path-bound unix datagram
// sockets the kernel answers SO_PEERCRED with the zero sentinel
// (pid 0, uid/gid -1) even on connected sockets that carried
// traffic -- verified empirically; socketpair endpoints do answer.
// The only truthful credential source for such sockets is
// SCM_CREDENTIALS ancillary data on received datagrams, so the
// unix datagram receive path harvests it into this table and
// sa_std_net_unix_datagram_peer_cred consults it. Entries are
// keyed by (handle, fd) and revalidated against the live registry
// on lookup, so a recycled handle/fd pair cannot resurrect a
// stale credential. All access under registry_mutex.




/// Unix datagram sockets in this std carry SO_PASSCRED from birth
/// so the receive path can harvest SCM_CREDENTIALS (see above).
/// Best effort: failure only means peer_cred reports NOT_FOUND
/// for a connected socket instead of answering with a wrong or
/// zero credential.
pub fn armPeerCredHarvest(fd: std.posix.fd_t) void {
    if (comptime !is_linux) return;
    setSocketOptBool(fd, SOLT.SOCKET, SO_PASSCRED, true) catch {};
}

/// Extract the sender credential from a recvmsg control chain
/// (SOL_SOCKET / SCM_CREDENTIALS), same walk as udp_recv_msg.

pub fn getSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32) !i32 {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(i32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}


pub fn getSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32) !u8 {
    var value: u8 = 0;
    var len: SockLenT = @sizeOf(u8);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u8)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32) !u32 {
    var value: u32 = 0;
    var len: SockLenT = @sizeOf(u32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, out: []u8) !void {
    var len: SockLenT = @intCast(out.len);
    const rc = std.os.linux.getsockopt(fd, level, optname, out.ptr, &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != out.len) return error.UnexpectedSize;
        },
        else => return error.InvalidArgument,
    }
}




pub fn socketIsStream(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.STREAM));
}

pub fn socketIsDatagram(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.DGRAM));
}


pub fn getUnixSockAddr(fd: std.posix.fd_t, peer: bool) !struct { addr: SockAddrUnT, len: SockLenT } {
    var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    var len: SockLenT = @sizeOf(SockAddrUnT);
    if (peer) {
        try lxGetpeername(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    } else {
        try lxGetsockname(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    }
    return .{ .addr = addr, .len = len };
}


// Parse one "::"-free half ("1:2:3" or trailing embedded IPv4) into out,
// returning the group count. Used only on FreeBSD (see parseIpv6Freebsd).

// Numeric IPv6 parser for FreeBSD: the old Ip6Address.resolve/parse and
// Address.resolveIp all reach if_nametoindex (unimplemented for freebsd in
// zig 0.14). Handles full, "::"-compressed and embedded-IPv4 forms.

// "addr" or "addr%zone" (numeric zone, or interface name via libc
// if_nametoindex which FreeBSD provides). Shared by parseIp6Address and
// parseIpv6Ascii on FreeBSD.






pub fn makeIpv4Membership(multicast_addr: NetAddress, interface_addr: NetAddress) IpMreqC {
    return .{
        .imr_multiaddr = .{ .s_addr = multicast_addr.in4AddrU32() },
        .imr_interface = .{ .s_addr = interface_addr.in4AddrU32() },
    };
}

pub fn makeIpv6Membership(multicast_addr: NetAddress, interface_index: u32) Ipv6MreqC {
    return .{
        .ipv6mr_multiaddr = multicast_addr.in6AddrBytes(),
        .ipv6mr_interface = interface_index,
    };
}




pub fn getResourceLocked(handle: u64) ?*Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= spawn.registry_slots.items.len) return null;
    if (spawn.registry_slots.items[idx]) |*resource| return resource;
    return null;
}

pub fn registerResourceLocked(resource: Resource) !u64 {
    for (spawn.registry_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            spawn.registry_slots.items[idx] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
        }
    }
    const idx = spawn.registry_slots.items.len;
    try spawn.registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
}

pub fn registerResource(resource: Resource) !u64 {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    return try registerResourceLocked(resource);
}









pub fn applyRawMode(term: *std.posix.termios) void {
    term.iflag.IGNBRK = false;
    term.iflag.BRKINT = false;
    term.iflag.PARMRK = false;
    term.iflag.ISTRIP = false;
    term.iflag.INLCR = false;
    term.iflag.IGNCR = false;
    term.iflag.ICRNL = false;
    term.iflag.IXON = false;
    term.iflag.IXOFF = false;
    term.oflag.OPOST = false;
    term.cflag.CSIZE = .CS8;
    term.cflag.PARENB = false;
    term.cflag.CREAD = true;
    term.lflag.ISIG = false;
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    term.lflag.IEXTEN = false;
    term.cc[@backingInt(std.posix.V.MIN)] = 1;
    term.cc[@backingInt(std.posix.V.TIME)] = 0;
}



// DEF-R5: the registry mutex guards the handle table only; it
// must never be held across a syscall that can block. The data
// path classifies a handle under the lock, snapshots the OS fd
// (or notes an in-memory kind), drops the lock, and only then
// performs the blocking read/write -- the same snapshot pattern
// sa_std_close and sa_std_net_tcp_accept already use in this
// file. Before this split, one goroutine parked in a blocking
// sa_std_read held the registry mutex for the whole wait, so
// every other goroutine's net IO (and every other registry
// user: poll_wait validation, writes, accepts, closes) stalled
// or spun behind it: with >= 2 goroutines blocked in net reads
// only the mutex holder was ever serviced, regardless of
// carrier count (slaredis registration A). In-memory kinds
// (.buffer/.process) never block and keep the locked path.

pub fn lockRegistry() void {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}


/// DEF-R5: snapshot a tcp_stream / udp_socket fd under the
/// registry lock and drop the lock before any blocking syscall
/// (see the IoPlan note above).
pub fn tcpStreamFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .tcp_stream => |s| s,
        else => null,
    };
}

pub fn udpSocketFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .udp_socket => |fd| fd,
        else => null,
    };
}

// Read once from a handle without holding the registry mutex
// across a blocking syscall (see the IoPlan note above).

/// Write to a handle without holding the registry mutex across
/// a blocking syscall. Per-kind semantics preserve the previous
/// locked implementation: fd writes are a single write(2),
/// while file writes write all bytes (sio.File.write is
/// writeAll).


fn statusFromTerm(term: sio.Child.Term) u32 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 130,
        .unknown => 127,
    };
}

fn argvFromBlob(allocator: std.mem.Allocator, blob: []const u8) ![]const []const u8 {
    var count: usize = 1;
    for (blob) |b| {
        if (b == 0) count += 1;
    }
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    var start: usize = 0;
    var index: usize = 0;
    while (start <= blob.len) {
        const end = std.mem.indexOfScalarPos(u8, blob, start, 0) orelse blob.len;
        if (end == start) {
            if (end == blob.len) break;
            start = end + 1;
            continue;
        }
        args[index] = blob[start..end];
        index += 1;
        if (end == blob.len) break;
        start = end + 1;
    }
    return args[0..index];
}

pub fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![]const []const u8 {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = argv_ptr orelse return error.InvalidArgument;
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    for (args, 0..) |*slot, index| {
        const entry = entries[index];
        const n = try lenAsUsize(entry.len);
        slot.* = if (n == 0) &.{} else entry.data[0..n];
    }
    return args;
}














pub fn waitStatusFromSiginfo(siginfo: std.posix.siginfo_t) u32 {
    const status = @as(u32, @intCast(siginfo.fields.common.second.sigchld.status));
    return switch (siginfo.code) {
        1 => (status & 0xff) << 8, // CLD_EXITED
        2 => status, // CLD_KILLED
        3 => status | 0x80, // CLD_DUMPED
        6 => 0xffff, // CLD_CONTINUED
        4, 5 => ((status & 0xff) << 8) | 0x7f, // CLD_TRAPPED / CLD_STOPPED
        else => 0,
    };
}




pub fn sendSignalToProcessGroup(pgid: std.posix.pid_t, signum: u8) !void {
    const target: std.posix.pid_t = -pgid;
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        lxKill(target, signum) catch |err| switch (err) {
            error.ProcessNotFound => {
                if (attempts >= 50) return err;
                sio.io().sleep(.fromNanoseconds(1 * std.time.ns_per_ms), .awake) catch {};
                continue;
            },
            else => return err,
        };
        return;
    }
}

fn errnoToSetupError(errno: std.posix.E) anyerror {
    return switch (errno) {
        .SUCCESS => unreachable,
        .INVAL => error.InvalidArgument,
        .PERM, .ACCES => error.PermissionDenied,
        .NOENT => error.FileNotFound,
        .NOMEM => error.OutOfMemory,
        .NOTDIR => error.NotDir,
        else => error.Unexpected,
    };
}






pub fn filePread(f: sio.File, buffer: []u8, offset: u64) !usize {
    return try f.inner.readPositional(sio.io(), &.{buffer}, offset);
}

pub fn filePreadAll(f: sio.File, buffer: []u8, offset: u64) !usize {
    var index: usize = 0;
    while (index != buffer.len) {
        const n = try f.inner.readPositional(sio.io(), &.{buffer[index..]}, offset + index);
        if (n == 0) return error.EndOfStream;
        index += n;
    }
    return index;
}

pub fn filePwrite(f: sio.File, buffer: []const u8, offset: u64) !usize {
    return try f.inner.writePositional(sio.io(), &.{buffer}, offset);
}

pub fn filePwriteAll(f: sio.File, buffer: []const u8, offset: u64) !void {
    return try f.inner.writePositionalAll(sio.io(), buffer, offset);
}

pub fn fileSeekBy(f: sio.File, offset: i64) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.Unsupported;
    } else {
        const rc = std.os.linux.lseek(f.inner.handle, 0, std.posix.SEEK.CUR);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Io;
        const cur: i64 = @bitCast(@as(u64, @intCast(rc)));
        const new_pos = cur + offset;
        if (new_pos < 0) return error.InvalidArgument;
        try f.seekTo(@as(u64, @intCast(new_pos)));
    }
}

pub fn fileSeekFromEnd(f: sio.File, offset: i64) !void {
    const len = try f.length();
    const new_pos = @as(i64, @intCast(len)) + offset;
    if (new_pos < 0) return error.InvalidArgument;
    try f.seekTo(@as(u64, @intCast(new_pos)));
}

pub fn fileGetPos(f: sio.File) !u64 {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.Unsupported;
    } else {
        const rc = std.os.linux.lseek(f.inner.handle, 0, std.posix.SEEK.CUR);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Io;
        return @as(u64, @intCast(rc));
    }
}

pub fn fileSetEndPos(f: sio.File, new_size: u64) !void {
    try f.inner.setLength(sio.io(), new_size);
}

// ---------------------------------------------------------------------------
// 0.17 compat: linux-syscall wrappers (old std.posix throwing helpers removed)
// and socket-address compat (old net Address type removed).
// Verified against /opt/zig/.../lib/std/os/linux.zig + Io/net.zig via probes.
// ---------------------------------------------------------------------------
pub fn errnoToAny(e: anytype) anyerror {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) unreachable;
    if (std.mem.eql(u8, n, "INTR")) return error.Interrupted;
    if (std.mem.eql(u8, n, "AGAIN")) return error.WouldBlock;
    if (std.mem.eql(u8, n, "BADF")) return error.InvalidHandle;
    if (std.mem.eql(u8, n, "ACCES")) return error.AccessDenied;
    if (std.mem.eql(u8, n, "PERM")) return error.PermissionDenied;
    if (std.mem.eql(u8, n, "NOENT")) return error.FileNotFound;
    if (std.mem.eql(u8, n, "EXIST")) return error.PathAlreadyExists;
    if (std.mem.eql(u8, n, "NOTDIR")) return error.NotDir;
    if (std.mem.eql(u8, n, "ISDIR")) return error.IsDir;
    if (std.mem.eql(u8, n, "NAMETOOLONG")) return error.NameTooLong;
    if (std.mem.eql(u8, n, "NOSPC")) return error.NoSpaceLeft;
    if (std.mem.eql(u8, n, "MFILE")) return error.ProcessFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NFILE")) return error.SystemFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NOMEM")) return error.SystemResources;
    if (std.mem.eql(u8, n, "INVAL")) return error.InvalidArgument;
    if (std.mem.eql(u8, n, "SRCH")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "CHILD")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "TIMEDOUT")) return error.ConnectionTimedOut;
    if (std.mem.eql(u8, n, "INPROGRESS")) return error.ConnectionPending;
    if (std.mem.eql(u8, n, "ALREADY")) return error.AlreadyConnected;
    if (std.mem.eql(u8, n, "CONNREFUSED")) return error.ConnectionRefused;
    if (std.mem.eql(u8, n, "CONNRESET")) return error.ConnectionResetByPeer;
    if (std.mem.eql(u8, n, "CONNABORTED")) return error.ConnectionAborted;
    if (std.mem.eql(u8, n, "NOTCONN")) return error.SocketNotConnected;
    if (std.mem.eql(u8, n, "NETUNREACH")) return error.NetworkUnreachable;
    if (std.mem.eql(u8, n, "HOSTUNREACH")) return error.HostUnreachable;
    if (std.mem.eql(u8, n, "ADDRINUSE")) return error.AddressInUse;
    if (std.mem.eql(u8, n, "ADDRNOTAVAIL")) return error.AddressNotAvailable;
    if (std.mem.eql(u8, n, "MSGSIZE")) return error.MessageTooBig;
    if (std.mem.eql(u8, n, "NOTSOCK")) return error.NotSocket;
    if (std.mem.eql(u8, n, "OPNOTSUPP")) return error.OperationNotSupported;
    if (std.mem.eql(u8, n, "AFNOSUPPORT")) return error.AddressFamilyNotSupported;
    if (std.mem.eql(u8, n, "PROTONOSUPPORT")) return error.ProtocolNotSupported;
    if (std.mem.eql(u8, n, "PIPE")) return error.BrokenPipe;
    if (std.mem.eql(u8, n, "NOTTY")) return error.NotATerminal;
    if (std.mem.eql(u8, n, "FBIG")) return error.FileTooBig;
    if (std.mem.eql(u8, n, "ROFS")) return error.ReadOnlyFileSystem;
    if (std.mem.eql(u8, n, "LOOP")) return error.SymLinkLoop;
    if (std.mem.eql(u8, n, "FAULT")) return error.Unexpected;
    if (std.mem.eql(u8, n, "BUSY")) return error.FileBusy;
    if (std.mem.eql(u8, n, "XDEV")) return error.RenameAcrossMountPoints;
    if (std.mem.eql(u8, n, "TXTBSY")) return error.FileBusy;
    return error.Unexpected;
}


pub fn lxCheck(rc: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    const e = std.os.linux.errno(rc);
    if (e != .SUCCESS) return lxErr(e);
    return rc;
}

// --- libc fallbacks (macOS/FreeBSD) ---------------------------------------

pub const libc = struct {
    extern "c" fn socket(domain: c_int, socket_type: c_int, protocol: c_int) c_int;
    extern "c" fn bind(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn listen(fd: c_int, backlog: c_int) c_int;
    extern "c" fn accept(fd: c_int, addr: ?*SockAddrT, len: ?*libc_socklen_t) c_int;
    extern "c" fn connect(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn shutdown(fd: c_int, how: c_int) c_int;
    extern "c" fn sendto(fd: c_int, buf: *const anyopaque, len: usize, flags: c_int, addr: ?*const SockAddrT, addrlen: libc_socklen_t) isize;
    extern "c" fn recvfrom(fd: c_int, buf: *anyopaque, len: usize, flags: c_int, addr: ?*SockAddrT, addrlen: ?*libc_socklen_t) isize;
    extern "c" fn sendmsg(fd: c_int, msg: *const MsghdrConstT, flags: c_int) isize;
    extern "c" fn getsockname(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getpeername(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: *anyopaque, optlen: *libc_socklen_t) c_int;
    extern "c" fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: libc_socklen_t) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
    extern "c" fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
    extern "c" fn readv(fd: c_int, iov: [*]const std.posix.iovec, iovcnt: c_int) isize;
    extern "c" fn writev(fd: c_int, iov: [*]const std.posix.iovec_const, iovcnt: c_int) isize;
    extern "c" fn dup(fd: c_int) c_int;
    extern "c" fn dup2(old: c_int, new: c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn chdir(path: [*:0]const u8) c_int;
    extern "c" fn chroot(path: [*:0]const u8) c_int;
    extern "c" fn setgroups(count: c_int, groups: [*]const std.c.gid_t) c_int;
    extern "c" fn setsid() std.c.pid_t;
    extern "c" fn setgid(gid: std.c.gid_t) c_int;
    extern "c" fn setuid(uid: std.c.uid_t) c_int;
    extern "c" fn setpgid(pid: std.c.pid_t, pgid: std.c.pid_t) c_int;
    extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    extern "c" fn unlink(path: [*:0]const u8) c_int;
    extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t) c_int;
    extern "c" fn fchmodat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t, flags: c_int) c_int;
    extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int;
    extern "c" fn futimens(fd: c_int, times: *const [2]std.posix.timespec) c_int;
    extern "c" fn kill(pid: std.c.pid_t, sig: c_int) c_int;
    extern "c" fn waitpid(pid: std.c.pid_t, status: *c_int, options: c_int) std.c.pid_t;
    extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn _exit(code: c_int) noreturn;
    extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
    extern "c" fn socketpair(domain: c_int, socket_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
    extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn lchown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn fchown(fd: c_int, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn mknod(path: [*:0]const u8, mode: std.c.mode_t, dev: std.c.dev_t) c_int;
};

pub fn libcErrRc(rc: anytype) !void {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
}


pub fn libcUsize(rc: isize) !usize {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub fn lxClose(fd: std.posix.fd_t) void {
    if (comptime is_wasm) return;
    if (comptime is_linux) {
        _ = std.os.linux.close(fd);
    } else {
        _ = libc.close(fd);
    }
}

pub fn lxWrite(fd: std.posix.fd_t, bytes: []const u8) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.write(fd, bytes.ptr, bytes.len));
    return try libcUsize(libc.write(fd, bytes.ptr, bytes.len));
}


pub fn lxReadv(fd: std.posix.fd_t, iov: []std.posix.iovec) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.readv(fd, iov.ptr, iov.len));
    return try libcUsize(libc.readv(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxWritev(fd: std.posix.fd_t, iov: []const std.posix.iovec_const) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.writev(fd, iov.ptr, iov.len));
    return try libcUsize(libc.writev(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxSocket(domain: u32, sock_type: u32, protocol: u32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.socket(domain, sock_type, protocol));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    return try libcFd(libc.socket(@intCast(domain), @intCast(sock_type), @intCast(protocol)));
}





pub fn lxShutdown(fd: std.posix.fd_t, how: i32) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.shutdown(fd, how));
        return;
    }
    try libcErrRc(libc.shutdown(fd, @intCast(how)));
}

pub fn lxSend(fd: std.posix.fd_t, bytes: []const u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, null, 0));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), null, 0));
}

pub fn lxRecv(fd: std.posix.fd_t, buf: []u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, null, null));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), null, null));
}

pub fn lxSendto(fd: std.posix.fd_t, bytes: []const u8, flags: u32, addr: ?*const SockAddrT, len: SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, addr, len));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), addr, @intCast(len)));
}

pub fn lxRecvfrom(fd: std.posix.fd_t, buf: []u8, flags: u32, addr: ?*SockAddrT, len: ?*SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, addr, len));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), addr, @ptrCast(len)));
}















pub fn lxUnlink(path: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.unlink(&z));
        return;
    }
    try libcErrRc(libc.unlink(&z));
}

pub fn lxMkdirat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.mkdirat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.mkdirat(dirfd, &z, @intCast(mode)));
}

pub fn lxFchmodat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.fchmodat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.fchmodat(dirfd, &z, @intCast(mode), 0));
}

pub fn lxLink(old: []const u8, new: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const old_z = try std.posix.toPosixPath(old);
    const new_z = try std.posix.toPosixPath(new);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.link(&old_z, &new_z));
        return;
    }
    try libcErrRc(libc.link(&old_z, &new_z));
}

pub fn lxFutimens(fd: std.posix.fd_t, times: *const [2]std.posix.timespec) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.futimens(fd, times));
        return;
    }
    try libcErrRc(libc.futimens(fd, times));
}

pub fn lxKill(pid: std.posix.pid_t, sig: u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.kill(pid, @fromBackingInt(@intCast(sig))));
        return;
    }
    try libcErrRc(libc.kill(@intCast(pid), @intCast(sig)));
}


pub fn lxGetpeername(fd: std.posix.fd_t, addr: *SockAddrT, len: *SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getpeername(fd, addr, len));
        return;
    }
    try libcErrRc(libc.getpeername(fd, addr, @ptrCast(len)));
}


pub fn lxEpollCreate1(flags: u32) !std.posix.fd_t {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    const rc = try lxCheck(std.os.linux.epoll_create1(flags));
    return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
}

pub fn lxEpollCtl(epfd: std.posix.fd_t, op: u32, fd: std.posix.fd_t, event: ?*std.os.linux.epoll_event) !void {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    _ = try lxCheck(std.os.linux.epoll_ctl(epfd, op, fd, event));
}

pub fn lxEpollWait(epfd: std.posix.fd_t, events: []std.os.linux.epoll_event, timeout_ms: i32) usize {
    if (comptime !is_linux) return 0;
    if (comptime is_wasm) return;
    const rc = std.os.linux.epoll_wait(epfd, events.ptr, @as(u32, @intCast(events.len)), timeout_ms);
    if (std.os.linux.errno(rc) != .SUCCESS) return 0;
    return rc;
}



// Old std.posix.execvpeZ: exec with PATH search. Reimplemented on execve.


// ---------------------------------------------------------------------------
// 0.17 compat: socket addresses (old net Address type removed).
// Raw sockaddr storage + constructors; DNS via std.Io.net.
// ---------------------------------------------------------------------------
pub const NetAddress = struct {
    storage: SockAddrStorageT = makeSockAddrStorage(),
    len: SockLenT = @sizeOf(SockAddrStorageT),

    pub fn sockAddr(self: *const NetAddress) *const SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn sockAddrMut(self: *NetAddress) *SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn getOsSockLen(self: NetAddress) SockLenT {
        return self.len;
    }

    pub fn getPort(self: NetAddress) u16 {
        return switch (self.storage.family) {
            AFT.INET => blk: {
                const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin.port);
            },
            AFT.INET6 => blk: {
                const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin6.port);
            },
            else => 0,
        };
    }

    pub fn initIp4(parts: [4]u8, port: u16) NetAddress {
        const sin = SockAddrInT{
            .port = std.mem.nativeToBig(u16, port),
            .addr = @bitCast(parts),
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrInT) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrInT)], std.mem.asBytes(&sin));
        return a;
    }

    pub fn initIp6(bytes: [16]u8, port: u16, flowinfo: u32, scope_id: u32) NetAddress {
        const sin6 = SockAddrIn6T{
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = flowinfo,
            .addr = bytes,
            .scope_id = scope_id,
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrIn6T) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrIn6T)], std.mem.asBytes(&sin6));
        return a;
    }

    pub fn initUnix(path: []const u8) !NetAddress {
        const off = @offsetOf(SockAddrUnT, "path");
        if (off + path.len + 1 > @sizeOf(SockAddrUnT)) return error.NameTooLong;
        var sun: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
        @memcpy(sun.path[0..path.len], path);
        sun.path[path.len] = 0;
        var a = NetAddress{ .len = @as(SockLenT, @intCast(off + path.len + 1)) };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn fromIp(ip: std.Io.net.IpAddress) NetAddress {
        return switch (ip) {
            .ip4 => |v4| initIp4(v4.bytes, v4.port),
            .ip6 => |v6| initIp6(v6.bytes, v6.port, v6.flow, v6.interface.index),
        };
    }

    pub fn resolveIp(host: []const u8, port: u16) !NetAddress {
        if (std.Io.net.IpAddress.parse(host, port)) |ip| {
            return fromIp(ip);
        } else |_| {}
        var list = try netGetAddressList(std.heap.page_allocator, host, port);
        defer list.deinit();
        if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
        return list.addrs[0];
    }

    pub fn unixPath(self: *const NetAddress) []const u8 {
        const sun: *const SockAddrUnT = @ptrCast(&self.storage);
        return std.mem.sliceTo(&sun.path, 0);
    }

    pub fn fromUnixSockaddr(sun: SockAddrUnT, len: SockLenT) NetAddress {
        var a = NetAddress{ .len = len };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn in6ScopeId(self: *const NetAddress) u32 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.scope_id;
    }

    pub fn in4AddrU32(self: *const NetAddress) u32 {
        const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
        return sin.addr;
    }

    pub fn in6AddrBytes(self: *const NetAddress) [16]u8 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.addr;
    }
};

const NetAddressList = struct {
    addrs: []NetAddress,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NetAddressList) void {
        self.allocator.free(self.addrs);
        self.addrs = &.{};
    }
};

pub fn netGetAddressList(allocator: std.mem.Allocator, host: []const u8, port: u16) !NetAddressList {
    if (std.Io.net.IpAddress.parse(host, port)) |ip| {
        const addrs = try allocator.alloc(NetAddress, 1);
        addrs[0] = NetAddress.fromIp(ip);
        return .{ .addrs = addrs, .allocator = allocator };
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    var qbuf: [16]std.Io.net.HostName.LookupResult = undefined;
    var q = std.Io.Queue(std.Io.net.HostName.LookupResult).init(&qbuf);
    hn.lookup(sio.io(), &q, .{ .port = port }) catch |err| switch (err) {
        error.UnknownHostName => return error.UnknownHostName,
        else => return err,
    };
    q.close(sio.io());
    var out: std.array_list.Managed(NetAddress) = .init(allocator);
    errdefer out.deinit();
    var drain: [16]std.Io.net.HostName.LookupResult = undefined;
    while (true) {
        const n = q.get(sio.io(), &drain, 0) catch |err| switch (err) {
            error.Closed => break,
            else => return err,
        };
        if (n == 0) break;
        for (drain[0..n]) |r| {
            if (r == .address) try out.append(NetAddress.fromIp(r.address));
        }
    }
    if (out.items.len == 0) {
        out.deinit();
        return error.HostLacksNetworkAddresses;
    }
    return .{ .addrs = try out.toOwnedSlice(), .allocator = allocator };
}

// ---------------------------------------------------------------------------
// 0.17 compat: portable file metadata. Linux keeps statx; other targets use
// the Io vtable stat (which maps to lstat/stat internally).
// ---------------------------------------------------------------------------









pub fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const n = std.fmt.printInt(&buf, value, actual_base, case, .{});
    const text = buf[0..n];
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{d:.[1]}", .{ value, @as(usize, @intCast(precision)) });
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatBool(value: bool) ![]u8 {
    return std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

pub fn formatBytes(bytes: []const u8) ![]u8 {
    return std.heap.page_allocator.dupe(u8, bytes);
}

pub fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

pub fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    var bytes = try std.heap.page_allocator.alloc(u8, left.len + right.len);
    if (left.len != 0) std.mem.copyForwards(u8, bytes[0..left.len], left);
    if (right.len != 0) std.mem.copyForwards(u8, bytes[left.len .. left.len + right.len], right);
    return bytes;
}


pub fn openOwnedBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .fmt = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

pub fn openOwnedByteBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

pub fn openOwnedEnvBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .env = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}



















































pub fn jsonStringValue(value: ?std.json.Value) []const u8 {
    const actual = value orelse return "";
    return switch (actual) {
        .string => |text| text,
        else => "",
    };
}





























pub fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}



const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

fn appendEnvVarJson(pairs: *std.array_list.Managed(EnvVarJson), entry: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    if (eq == 0) return;
    try pairs.append(.{ .key = entry[0..eq], .value = entry[eq + 1 ..] });
}

pub fn envVarsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    var pairs = std.array_list.Managed(EnvVarJson).init(allocator);
    defer pairs.deinit();

    {
        var i: usize = 0;
        while (environ[i] != null) : (i += 1) {
            try appendEnvVarJson(&pairs, std.mem.span(environ[i].?));
        }
    }

    return std.json.Stringify.valueAlloc(allocator, pairs.items, .{});
}

pub fn processArgsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        const file = sio.openFileAbsolute("/proc/self/cmdline", .{}) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => null,
            else => return err,
        };
        if (file) |cmdline_file| {
            defer cmdline_file.close();
            const cmdline = try cmdline_file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(cmdline);

            var args = std.array_list.Managed([]const u8).init(allocator);
            defer args.deinit();
            var it = std.mem.splitScalar(u8, cmdline, 0);
            while (it.next()) |arg| {
                if (arg.len == 0) continue;
                try args.append(arg);
            }
            return std.json.Stringify.valueAlloc(allocator, args.items, .{});
        }
    }

    const args = try sio.argsAlloc(allocator);
    defer sio.argsFree(allocator, args);
    return std.json.Stringify.valueAlloc(allocator, args, .{});
}

pub fn envSplitPathsJsonAlloc(allocator: std.mem.Allocator, path_list: []const u8) ![]u8 {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, path_list, ':');
    while (it.next()) |part| {
        try parts.append(part);
    }

    return std.json.Stringify.valueAlloc(allocator, parts.items, .{});
}

pub fn envJoinPathsJsonAlloc(allocator: std.mem.Allocator, paths_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, paths_json, .{});
    defer parsed.deinit();

    for (parsed.value) |path| {
        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    }

    return std.mem.join(allocator, ":", parsed.value);
}







// NOTE: sa_http_client_* used to be provided by the http-client plugin
// and deliberately left undefined here (a stub once shadowed it). Since
// 2026-10-24 the real implementation is built into sa_std
// (src/runtime/sa_http_client.zig, migrated from the plugin under the
// all-cores-built-in doctrine); the plugin keeps only framework wraps.

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

// --- Checked i64 arithmetic (sa_std/num.sai) ------------------------------
// Exact-result arithmetic with Rust `overflow-checks = true` semantics:
// on overflow the operation traps instead of wrapping. The SA-level
// mirror (sa_std/num.sal NUM_*_CHECKED macros) traps with
// panic(PANIC_ARITH_OVERFLOW = 9001); a native extern has no SA panic
// channel, so the trap here is a diagnostic on stderr plus process
// abort -- never a wrapped result, never a silent status (the .sai
// signature returns the bare i64 and has no status channel).
fn saNumCheckedTrap(comptime symbol: []const u8, a: i64, b: i64) noreturn {
    std.debug.print("[sa-std] {s}({d}, {d}): i64 overflow, trapping (PANIC_ARITH_OVERFLOW=9001)\n", .{ symbol, a, b });
    std.process.abort();
}

pub export fn sa_num_add_checked(a: i64, b: i64) i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_add_checked", a, b);
    return result[0];
}

pub export fn sa_num_sub_checked(a: i64, b: i64) i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_sub_checked", a, b);
    return result[0];
}

pub export fn sa_num_mul_checked(a: i64, b: i64) i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_mul_checked", a, b);
    return result[0];
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}










pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    sio.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}














// SIMD hex decoder: native bulk-decode fast path (mirrors the sa_hexdec
// JS host-codec shim contract). Decodes ASCII hex pairs into bytes at
// 32 input chars per vector iteration with a scalar tail. Stops at the
// first invalid char or odd trailing nibble and returns the bytes
// written so far; clean even-length input of n chars yields exactly
// n/2. Caller must provide at least n/2 bytes of output.
fn hexSimdNibbleVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return null;
}

pub export fn sa_hexdec_simd(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64 {
    const input = constBytes(in_ptr, in_len) catch return 0;
    const n = input.len;
    if (n == 0) return 0;
    const out_p = out_ptr orelse return 0;
    const out = out_p[0 .. n / 2];
    const V32 = @Vector(32, u8);
    const z0: V32 = @splat(@as(u8, '0'));
    const z9: V32 = @splat(@as(u8, '9'));
    const zA: V32 = @splat(@as(u8, 'A'));
    const zF: V32 = @splat(@as(u8, 'F'));
    const za: V32 = @splat(@as(u8, 'a'));
    const zf: V32 = @splat(@as(u8, 'f'));
    const ten: V32 = @splat(@as(u8, 10));
    const one: V32 = @splat(@as(u8, 1));
    const zero: V32 = @splat(@as(u8, 0));
    const four: @Vector(16, u8) = @splat(@as(u8, 4));
    const even_idx: [16]i32 = .{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 };
    const odd_idx: [16]i32 = .{ 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 };
    var i: usize = 0;
    var w: usize = 0;
    while (i + 32 <= n) {
        const chunk: V32 = input[i..][0..32].*;
        const in09 = @select(u8, chunk >= z0, @select(u8, chunk <= z9, one, zero), zero);
        const inAF = @select(u8, chunk >= zA, @select(u8, chunk <= zF, one, zero), zero);
        const inaf = @select(u8, chunk >= za, @select(u8, chunk <= zf, one, zero), zero);
        const valid = in09 | inAF | inaf;
        if (@reduce(.Min, valid) == 0) break;
        const nib = in09 * (chunk -% z0) + inAF * (chunk -% (zA -% ten)) + inaf * (chunk -% (za -% ten));
        const evens = @shuffle(u8, nib, @as(V32, undefined), even_idx);
        const odds = @shuffle(u8, nib, @as(V32, undefined), odd_idx);
        const joined: @Vector(16, u8) = (evens << four) | odds;
        out[w..][0..16].* = joined;
        i += 32;
        w += 16;
    }
    while (i + 2 <= n) {
        const hi = hexSimdNibbleVal(input[i]) orelse break;
        const lo = hexSimdNibbleVal(input[i + 1]) orelse break;
        out[w] = (hi << 4) | lo;
        i += 2;
        w += 1;
    }
    return @intCast(w);
}




// SIMD base64 decoder: native bulk-decode fast path. Decodes clean
// A-Za-z0-9+/ quanta at 32 input chars per vector iteration with a
// scalar tail. Stops at the first non-alphabet char (including '=')
// and returns the bytes written so far; clean input of n chars with
// n % 4 == 0 yields exactly n/4*3. Caller must provide that many bytes.

extern fn sa_cpu_has_avx2() c_int;
extern fn sa_b64dec_avx2(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64;






// Bulk substring search for native peers (mirrors the sa_mfind_u8 JS
// fused shim contract): returns the first index of needle in haystack,
// or hay_len on miss (one-past-end sentinel, always representable).
// Empty needle matches at 0 (memmem semantics). Delegates to the Zig
// standard library search (library-grade, memchr-class).
pub export fn sa_mfind_u8(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) u64 {
    const hay = constBytes(hay_ptr, hay_len) catch return hay_len;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return hay.len;
    if (ndl.len == 0) return 0;
    if (ndl.len > hay.len) return hay.len;
    if (std.mem.indexOf(u8, hay, ndl)) |idx| return @intCast(idx);
    return hay.len;
}
















/// Zero-padded decimal append. (std.fmt `{d:04}` on 0.14 misplaces the
/// sign, emitting `+` for positives, so ISO dates pad manually instead.)
fn appendPadded(out: *std.array_list.Managed(u8), val: i64, width: usize) !void {
    if (val < 0) {
        try out.append('-');
        const rest = if (width > 0) width - 1 else 0;
        // Years never approach minInt; negation is safe here.
        return appendPadded(out, -val, rest);
    }
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < width) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// UTC `YYYY-MM-DDTHH:MM:SS.sssZ` append shared by the ISO formatters.
pub fn appendIsoUtc(out: *std.array_list.Managed(u8), year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, milli: i64) !void {
    try appendPadded(out, year, 4);
    try out.append('-');
    try appendPadded(out, month, 2);
    try out.append('-');
    try appendPadded(out, day, 2);
    try out.append('T');
    try appendPadded(out, hour, 2);
    try out.append(':');
    try appendPadded(out, minute, 2);
    try out.append(':');
    try appendPadded(out, second, 2);
    try out.append('.');
    try appendPadded(out, milli, 3);
    try out.append('Z');
}


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

const icu_err_overflow: c_int = 15;

fn unicodeNormalizerForForm(form: i32) ?*anyopaque {
    var err: c_int = 0;
    const inst = switch (form) {
        0 => unorm2_getNFCInstance_74(&err),
        1 => unorm2_getNFDInstance_74(&err),
        2 => unorm2_getNFKCInstance_74(&err),
        3 => unorm2_getNFKDInstance_74(&err),
        else => @panic("sa_unicode_normalize: invalid form code"),
    };
    if (err > 0 or inst == null) @panic("sa_unicode_normalize: ICU instance failed");
    return inst;
}

pub export fn sa_unicode_normalize(text: ?[*]const u8, text_len: u64, form: i32, out: ?[*]u8, out_cap: u64) i64 {
    if (text_len == 0) return 0;
    if (text_len > 0x7fffffff) @panic("sa_unicode_normalize: input too long");
    const input = constBytes(text, text_len) catch @panic("sa_unicode_normalize: null input");
    const norm = unicodeNormalizerForForm(form);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // UTF-8 -> UTF-16. UTF-16 units never exceed UTF-8 bytes (1-byte char
    // -> 1 unit; 4-byte char -> 2 units), so text_len units always suffice.
    const utf16_cap: c_int = @intCast(text_len);
    const utf16 = alloc.alloc(u16, @as(usize, @intCast(text_len))) catch @panic("sa_unicode_normalize: alloc failed");
    var utf16_len: c_int = 0;
    var err: c_int = 0;
    _ = u_strFromUTF8_74(utf16.ptr, utf16_cap, &utf16_len, input.ptr, utf16_cap, &err);
    if (err > 0) @panic("sa_unicode_normalize: invalid UTF-8 input");

    // Normalize in UTF-16. Decomposition can expand, so grow on overflow
    // (unorm2_normalize_74 returns the needed length on overflow).
    var norm_cap: usize = @as(usize, @intCast(utf16_len)) * 2;
    if (norm_cap < 16) norm_cap = 16;
    var norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
    err = 0;
    var norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
    if (err == icu_err_overflow) {
        if (norm_len <= 0) @panic("sa_unicode_normalize: ICU normalize failed");
        norm_cap = @intCast(norm_len);
        norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
        err = 0;
        norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
        if (err != 0) @panic("sa_unicode_normalize: ICU normalize failed");
    } else if (err > 0) {
        @panic("sa_unicode_normalize: ICU normalize failed");
    }

    // Measure the UTF-8 length (destCapacity 0 query), then fill or report.
    var utf8_len: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(null, 0, &utf8_len, norm_buf.ptr, norm_len, &err);
    if (err > 0 and err != icu_err_overflow) @panic("sa_unicode_normalize: ICU UTF-8 measure failed");
    if (out_cap == 0 or out == null) return utf8_len;
    if (@as(u64, @intCast(utf8_len)) > out_cap) return utf8_len;
    var written: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(out.?, @intCast(out_cap), &written, norm_buf.ptr, norm_len, &err);
    if (err > 0) @panic("sa_unicode_normalize: ICU UTF-8 convert failed");
    return written;
}

// Host presence probing (lazy const-slot design, Phase 0; JEV js_shim_native_zero).
// SA native execution runs under the sa interpreter/LLVM with no JS host
// global, so "is Bun" is definitionally false there. Returning 0 always is
// the contract, not a placeholder. The JS target gets a shim in emit_js.zig
// returning typeof Bun !== "undefined" ? 1 : 0. Env-sniffing was
// JEV-rejected (Bun sets no distinctive environment variable by default).
// The SA interpreter cannot run externs (UnsupportedExtern); this function
// executes under build-exe (LLVM), like sa_unicode_normalize above.
pub export fn sa_host_is_bun() i32 {
    return 0;
}


















/// Shared civil split: i64 unix millis to (days since epoch, millis
/// within day, Hinnant y/m/d, h/mi/s/ms). Negative inputs fold via
/// floored division; field order matches the getters below.
const CivilParts = struct {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    milli: i64,
    days: i64,
};

pub fn civilParts(ms: i64) CivilParts {
    const ms_per_day: i64 = 86400000;
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    return .{
        .year = if (month <= 2) y + 1 else y,
        .month = month,
        .day = doy - @divFloor(153 * mp + 2, 5) + 1,
        .hour = @divFloor(day_ms, 3600000),
        .minute = @divFloor(@mod(day_ms, 3600000), 60000),
        .second = @divFloor(@mod(day_ms, 60000), 1000),
        .milli = @mod(day_ms, 1000),
        .days = days,
    };
}

// JS `Date.toISOString` shape for an i64 unix-millis value: UTC
// `YYYY-MM-DDTHH:MM:SS.sssZ` (millis precision, zero-padded; years
// 0..9999 exact, larger years print unpadded-past-4 like the denoise
// path). Negative inputs (pre-1970) fold correctly via floored
// division (Howard Hinnant civil_from_days). Fresh buffer handle read
// back via `sa_fmt_buffer_data`/`sa_fmt_buffer_len` like concat.

// Strict-ISO `Date.parse`: `YYYY-MM-DD[THH:MM:SS[.sss]][Z|±HH:MM]`
// to unix millis. Plain i32 status (0 ok, 2 invalid); range-checked
// (leap days, h<24, m/s<60); date-only means UTC midnight per JS.
// Inverse Hinnant days_from_civil; years 0..9999 keep i64 arithmetic
// exact (bounded well inside range, no checked ops needed).

/// JS Date getters over i64 unix millis (UTC; month 0-based like JS,
/// day 0=Sunday like JS: 1970-01-01 was a Thursday).








pub const weekdayNames = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
pub const monthNames = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub fn appendTwo(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 2) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn appendFour(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 4) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// Fixed UTC string forms for Date toString/toDateString/toTimeString/
/// toUTCString (fmt 0..3), byte-exact with Node under UTC. Years use the
/// same 4-digit zero pad as the ISO path (documented bound 0..9999).

pub fn daysFromCivil(y_in: i64, m_in: i64, d: i64) i64 {
    const y: i64 = if (m_in <= 2) y_in - 1 else y_in;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(m_in - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

// JS Date setters over i64 unix millis (field 0..6). Components apply
// then normalize with floored divmod, so out-of-range values roll over
// exactly like JS (setMonth(13), setDate(0), setHours(25), negatives).
// Unknown field ids return the input unchanged (frontends only ever
// send 0..6 via fixed table extras).









// Compatibility shims for the rosetta demos that model host APIs directly.
pub fn fd_open(path_ptr: ?[*]const u8) callconv(.c) i32 {
    _ = path_ptr;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_read(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_close(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub fn mmap(fd: i32, len: i32) callconv(.c) ?[*]u8 {
    _ = fd;
    _ = len;
    last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub fn munmap(map: ?[*]u8, len: i32) callconv(.c) i32 {
    _ = map;
    _ = len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    last_error = SA_STD_OK;
    return sig;
}









pub fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) callconv(.c) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlsym_cookie[0..].ptr;
}

pub fn dlclose(handle: ?[*]u8) callconv(.c) i32 {
    _ = handle;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}





pub fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) callconv(.c) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sqlite3_step(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return 1;
}

pub fn sqlite3_finalize(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

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




























































const ProcessOutputStream = enum { stdout, stderr };

pub fn readProcessOutput(handle: u64, stream: ProcessOutputStream, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.capture_output or !proc.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
            const src = switch (stream) {
                .stdout => proc.stdout_buf,
                .stderr => proc.stderr_buf,
            };
            const pos_ptr = switch (stream) {
                .stdout => &proc.stdout_pos,
                .stderr => &proc.stderr_pos,
            };
            if (pos_ptr.* >= src.len) return finish(SA_STD_OK);
            const remaining = src.len - pos_ptr.*;
            const copy_len = @min(output.len, remaining);
            @memcpy(output[0..copy_len], src[pos_ptr.* .. pos_ptr.* + copy_len]);
            pos_ptr.* += copy_len;
            if (out_read) |ptr| ptr.* = @as(u64, @intCast(copy_len));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}









pub export fn sa_std_fd_from_raw(fd: i32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .owned_fd = .{ .fd = @as(std.posix.fd_t, @intCast(fd)) } }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}


pub export fn sa_std_fd_close_raw(fd: i32) i32 {
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    lxClose(@as(std.posix.fd_t, @intCast(fd)));
    return finish(SA_STD_OK);
}


pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}





















// W1-DEF-IO-BUFFER-API: io buffers are registry handles, the same
// BufferHandle resources sa_io_read_line registers and the
// sa_fs_read_buffer_* family already serves. The old raw-pointer
// form expected a *BufferHandle struct that no producer on this
// surface ever hands out (read_line returns a handle), and free
// ignored its argument entirely. All three now resolve the handle
// through the registry, sharing the fs family's implementation.








/// Atomic create-exclusive open (2026-10-26): read|write|create with
/// O_EXCL merged through custom flags. An existing path fails with
/// SA_STD_ERR_ALREADY_EXISTS (via error.PathAlreadyExists in mapError),
/// which lock-file protocols need to tell "lost the race" apart from a
/// generic IO failure.

































pub fn metadataModeMatches(handle: u64, mode_bits: u64) u8 {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if ((@as(u64, @intCast(metadata.raw.mode)) & std.posix.S.IFMT) == mode_bits) 1 else 0,
        else => 0,
    };
}

pub fn mkdirPathWithMode(path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (path.len == 0) return error.BadPathName;

    var index: usize = if (path[0] == '/') 1 else 0;
    while (index < path.len and path[index] == '/') : (index += 1) {}

    while (index <= path.len) {
        var next = index;
        while (next < path.len and path[next] != '/') : (next += 1) {}
        if (next > 0) {
            const prefix = path[0..next];
            if (prefix.len != 0 and !(prefix.len == 1 and prefix[0] == '/')) {
                // Compared, not switched on: lxMkdirat's inferred
                // error set on wasm lacks PathAlreadyExists (its
                // wasm branch returns only error.Unsupported), and a
                // catch-switch arm must name a set member.
                lxMkdirat(std.posix.AT.FDCWD, prefix, mode) catch |err| {
                    if (err != error.PathAlreadyExists) return err;
                };
            }
        }
        if (next == path.len) break;
        index = next + 1;
        while (index < path.len and path[index] == '/') : (index += 1) {}
    }
}


































































/// One mkdir -p segment: create the directory, or accept an existing
/// one only when it really is a directory. An existing non-directory
/// reports PathAlreadyExists (final segment) or fails the next
/// segment with NotDir; neither is a silent success.
fn mkdirPOne(prefix: []const u8) !void {
    // Compared, not switched on: see the wasm error-set note at the
    // other lxMkdirat call site.
    lxMkdirat(std.posix.AT.FDCWD, prefix, 0o777) catch |err| {
        if (err == error.PathAlreadyExists) {
            const stat = try sio.cwd().statFile(prefix);
            if (stat.kind != .directory) return error.PathAlreadyExists;
        } else return err;
    };
}

pub fn mkdirP(path: []const u8) !void {
    if (path.len == 0) return error.InvalidArgument;
    var index: usize = 0;
    while (index <= path.len) {
        const at_boundary = index == path.len or path[index] == '/';
        if (at_boundary and index > 0) {
            const prefix = path[0..index];
            if (!std.mem.eql(u8, prefix, "/") and !std.mem.eql(u8, prefix, ".")) {
                try mkdirPOne(prefix);
            }
        }
        index += 1;
    }
}

/// mkdir -p (2026-10-26): create every missing directory along the
/// path. Existing directories along the way (including the final
/// segment) are success; the TS mkdirSync(recursive) counterpart.










pub fn timespecFromUnixMs(unix_ms: i64) !Timespec {
    const sec = @divFloor(unix_ms, 1000);
    const rem_ms = @mod(unix_ms, 1000);
    const sec_value = std.math.cast(TimespecSec, sec) orelse return error.InvalidArgument;
    const nsec_value = std.math.cast(TimespecNsec, rem_ms * 1_000_000) orelse return error.InvalidArgument;
    return .{ .sec = sec_value, .nsec = nsec_value };
}




pub fn chownId(value: u32, enabled: u32) std.c.uid_t {
    return if (enabled != 0) @as(std.c.uid_t, @intCast(value)) else ~@as(std.c.uid_t, 0);
}

pub fn groupId(value: u32, enabled: u32) std.c.gid_t {
    return if (enabled != 0) @as(std.c.gid_t, @intCast(value)) else ~@as(std.c.gid_t, 0);
}

pub fn finishErrnoAny(e: anytype) i32 {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) return finish(SA_STD_OK);
    if (std.mem.eql(u8, n, "INTR")) return finish(SA_STD_ERR_IO);
    if (std.mem.eql(u8, n, "BADF")) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (std.mem.eql(u8, n, "ACCES") or std.mem.eql(u8, n, "PERM") or std.mem.eql(u8, n, "ROFS")) return finish(SA_STD_ERR_ACCESS);
    if (std.mem.eql(u8, n, "NOENT") or std.mem.eql(u8, n, "NOTDIR")) return finish(SA_STD_ERR_NOT_FOUND);
    if (std.mem.eql(u8, n, "FAULT") or std.mem.eql(u8, n, "INVAL") or std.mem.eql(u8, n, "NAMETOOLONG") or std.mem.eql(u8, n, "LOOP")) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (std.mem.eql(u8, n, "NOMEM")) return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_ERR_IO);
}

pub fn finishChownErrno(rc: usize) i32 {
    return finishErrnoAny(std.os.linux.errno(rc));
}

pub fn chownPath(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32, nofollow: bool) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    if (comptime is_linux) {
        const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
        const flags: u32 = if (nofollow) std.os.linux.AT.SYMLINK_NOFOLLOW else 0;
        const rc = std.os.linux.syscall5(
            .fchownat,
            @as(usize, @bitCast(@as(isize, std.os.linux.AT.FDCWD))),
            @intFromPtr(&path_z),
            chownId(uid, has_uid),
            groupId(gid, has_gid),
            flags,
        );
        switch (std.os.linux.errno(rc)) {
            .INTR => return chownPath(path_ptr, path_len, uid, gid, has_uid, has_gid, nofollow),
            else => return finishChownErrno(rc),
        }
    }
    const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
    const rc = if (nofollow)
        libc.lchown(&path_z, chownId(uid, has_uid), groupId(gid, has_gid))
    else
        libc.chown(&path_z, chownId(uid, has_uid), groupId(gid, has_gid));
    return finishErrnoAny(std.posix.errno(rc));
}













// Reverse DNS lookup (getnameinfo, NI_NAMEREQD) for a resolved address
// handle produced by sa_std_net_to_socket_addr_list/_first or a stream's
// peer/local addr. Output semantics mirror sa_std_net_hostname: call with
// (null, 0, &len) to size the buffer; SA_STD_ERR_TRUNCATED when it does
// not fit. SA_STD_ERR_IO when the address has no name (NXDOMAIN / no PTR).










// Interest/readiness bits for sa_std_net_poll_wait. The interest
// mask (input) and the readiness mask (output) share the read and
// write bits; the error bit is readiness-only.

/// Largest readiness set accepted by one sa_std_net_poll_wait call.
/// Larger connection sets are served by waiting on slices of the
/// set in rotation; the cap is loud (invalid argument), never a
/// silent truncation.
pub const poll_wait_stack_handles: usize = 256;

// Block until at least one of the given socket handles (TCP
// streams, TCP listeners, UDP sockets) is ready for the requested
// operations, or timeout_ms elapses (0 = return immediately,
// negative = wait indefinitely). ready[i] receives the readiness
// mask for handles[i] (0 = not ready) and out_ready_count the
// number of ready entries. A hangup reports READ|ERROR so an
// event loop attempts the read and observes EOF. Level-triggered
// only: readiness is re-evaluated on every call, which is what
// lets an event loop replace sleep-polling AND the per-round
// scan of every connection with a single wait over exactly the
// ready set. Handles must outlive the call. Native only; WASM
// returns SA_STD_ERR_UNSUPPORTED.








// SO_KEEPALIVE on a connected TCP stream. Codex's socket2 users enable this to
// keep idle upstream connections alive; exposed here so SA callers match parity.


// Tune the Linux TCP keepalive timers (idle before first probe, interval
// between probes, probe count before dropping). All three are in whole units
// (seconds for idle/interval, count for cnt) matching the kernel option ABI.

// SO_REUSEADDR on a TCP listener handle (or UDS listener, which shares the
// tcp_listener resource kind). Allows rebinding a TIME_WAIT address.

// SO_REUSEPORT on a TCP listener handle for load-balanced multi-acceptor setups.



















// Raw-socket creation (wave-3 fill; the missing primitive BE
// registered for the ICMP transport half). domain / sock_type /
// protocol are the raw OS numbers (AF_INET=2 / AF_INET6=10,
// SOCK_RAW=3 / SOCK_DGRAM=2, IPPROTO_ICMP=1 / IPPROTO_ICMPV6=58 on
// Linux), the same raw-number convention as the sockopt passthrough.
// SOCK_DGRAM is admitted alongside SOCK_RAW because that is the
// Linux ping-socket form of an ICMP socket; SOCK_STREAM and every
// other type are rejected loudly. The socket is registered as a
// datagram-kind (udp_socket) handle, so the existing datagram
// surfaces apply unchanged: udp_send_to / udp_recv_from /
// udp_set_read_timeout, the sockopt passthrough, fd detach
// (sa_std_fd_into_raw) and sa_std_close. Permission failures from
// socket(2) (root / CAP_NET_RAW for SOCK_RAW, ping_group_range for
// the ping form) surface as their loud status, never a fake handle.
// Linux + libc platforms; WASI returns SA_STD_ERR_UNSUPPORTED and
// the Windows root does not implement it (see
// docs/runtime_abi_windows_unsupported.txt).

pub fn lxSendfile(out_fd: std.posix.fd_t, in_fd: std.posix.fd_t, offset: *u64, count: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        var off: i64 = @intCast(offset.*);
        const rc = try lxCheck(std.os.linux.sendfile(out_fd, in_fd, &off, count));
        offset.* = @intCast(off);
        return rc;
    }
    return error.Unsupported;
}

// Zero-copy file-to-socket send (sendfile(2); wave-3 fill -- the
// surface was verified absent tree-wide before this addition).
// Sends up to `count` bytes of `file` starting at `offset` over the
// TCP stream, looping over partial sends; the file's own position is
// never used or moved (the offset travels in/out explicitly, so one
// file handle can serve many sends). out_sent receives the byte
// total actually sent: it equals `count` unless the file ended
// first, which is data (SA_STD_OK with a short count), never a
// silent truncation of the return contract. out_next_offset
// (optional) receives offset + out_sent. The stream's write timeout
// is NOT applied (sendfile has no per-call deadline here); a
// blocking stream blocks as the kernel dictates. Linux only:
// other platforms return SA_STD_ERR_UNSUPPORTED (the Windows root
// does not implement it; see the ABI unsupported manifest).



















































// ---------------------------------------------------------------------------
// Generic socket-option passthrough + datagram receive enhancements
// (wave-2 fill). The passthrough is the Python net census's
// highest-value single gap (one pair of functions covers every
// option without a dedicated wrapper); udp_recv_msg / udp_recv_multi
// are the Unreal net census datagram trio (pktinfo, packet
// timestamp, RecvMulti); unix_datagram_peer_cred completes the
// SO_PEERCRED face the Java census named (the stream form,
// sa_std_net_unix_stream_peer_cred, already exists below).
// ---------------------------------------------------------------------------





// out_flags bits of sa_std_net_udp_recv_msg; mirrored as
// SA_NET_RECV_MSG_* in sa_std/net.sla.
pub const recv_msg_flag_pktinfo: u32 = 1;
pub const recv_msg_flag_timestamp: u32 = 2;
pub const recv_msg_flag_ctrunc: u32 = 4;
pub const recv_msg_flag_trunc: u32 = 8;

// Linux control-message numbers the parser keys on (asm-generic /
// in.h values; net.sla pins the SLA-facing names). std.os.linux
// does not name SO_TIMESTAMP, so the literal is spelled out here.
pub const cmsg_level_ip: i32 = 0; // IPPROTO_IP
pub const cmsg_level_ipv6: i32 = 41; // IPPROTO_IPV6
pub const cmsg_type_ip_pktinfo: i32 = 8; // IP_PKTINFO
pub const cmsg_type_ipv6_pktinfo: i32 = 50; // IPV6_PKTINFO
pub const cmsg_type_timestamp: i32 = 29; // SO_TIMESTAMP



pub const recv_multi_max_msgs: usize = 64;







pub fn parsePortAscii(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + @as(u32, byte - '0');
        if (value > std.math.maxInt(u16)) return null;
    }
    return @as(u16, @intCast(value));
}



pub fn writeIpv6SegmentsNative(out: []u8, octets: *const [16]u8) void {
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        const seg = std.mem.readInt(u16, octets[index * 2 ..][0..2], .big);
        // Match SA `store ... as u16` host layout (x86_64 little-endian tests).
        std.mem.writeInt(u16, out[index * 2 ..][0..2], seg, .little);
    }
}

pub fn parseIpv6Ascii(text: []const u8) ?struct { octets: [16]u8, scope_id: u32 } {
    // FreeBSD: Ip6Address.resolve reaches unimplemented if_nametoindex.
    if (comptime builtin.os.tag == .freebsd) {
        const parsed = parseIp6FreebsdParts(text) orelse return null;
        return .{ .octets = parsed.addr, .scope_id = parsed.scope_id };
    }
    const parsed = std.Io.net.IpAddress.resolve(sio.io(), text, 0) catch return null;
    return switch (parsed) {
        .ip6 => |v6| .{ .octets = v6.bytes, .scope_id = v6.interface.index },
        .ip4 => null,
    };
}

pub fn parseSocketAddrV6Ascii(text: []const u8) ?struct { octets: [16]u8, port: u16, scope_id: u32 } {
    if (text.len < 4 or text[0] != '[') return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return null;
    if (close == 0 or close + 1 >= text.len or text[close + 1] != ':') return null;
    const ip_text = text[1..close];
    if (ip_text.len == 0) return null;
    const port = parsePortAscii(text[close + 2 ..]) orelse return null;
    const parsed = parseIpv6Ascii(ip_text) orelse return null;
    return .{
        .octets = parsed.octets,
        .port = port,
        .scope_id = parsed.scope_id,
    };
}



pub fn readIpv6SegmentsNative(raw: *const [16]u8) [8]u16 {
    var segments: [8]u16 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        segments[i] = std.mem.readInt(u16, raw[i * 2 ..][0..2], .little);
    }
    return segments;
}

pub fn formatIpv6Segments(buffer: []u8, segments: *const [8]u16) ![]u8 {
    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;
    for (segments.*, 0..) |segment, index| {
        if (segment == 0) {
            if (current_len == 0) current_start = index;
            current_len += 1;
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
        } else {
            current_len = 0;
        }
    }
    if (longest_len < 2) {
        longest_start = 8;
        longest_len = 0;
    }

    var w: std.Io.Writer = .fixed(buffer);
    var i: usize = 0;
    var abbreviated = false;
    while (i < segments.len) : (i += 1) {
        if (i == longest_start) {
            if (!abbreviated) {
                try w.writeAll(if (i == 0) "::" else ":");
                abbreviated = true;
            }
            i += longest_len - 1;
            continue;
        }
        if (abbreviated) abbreviated = false;
        try w.print("{x}", .{segments[i]});
        if (i != segments.len - 1) try w.writeByte(':');
    }
    return w.buffered();
}

// sa_net_format_ascii_batch_v1















// Float math for frontends (v0.24a; Haxe Math.* surface).
// Pure f64 functions; random yields [0, 1) from 53 crypto bits.




































// Single-byte string from a char code (JS `String.fromCharCode` over the
// subset's byte-oriented strings; exact inverse of byte `charCodeAt`).
// Only the low byte is stored (documented); returns a buffer handle read
// back via `sa_fmt_buffer_data`/`sa_fmt_buffer_len` like concat.

// JS `String.prototype.indexOf` over byte-oriented strings: first needle
// index at/after `from`, or -1. Empty needle yields min(from, hay.len).
// `from` arrives as u64 (frontends convert via asU64Arg); clamped defensively.

// JS `String.prototype.lastIndexOf`: last needle index at/before `from`
// (`from` clamped to hay.len), or -1. Empty needle yields the clamped `from`.

// JS `String.prototype.startsWith` (no position arg in the subset): 1/0.

// JS `String.prototype.endsWith`: 1/0.

// JS `String.prototype.toLowerCase` over the subset's byte-oriented
// strings: ASCII A-Z folds to a-z, all other bytes pass through
// (documented; full Unicode lower is refused at the frontend).
// Returns a fresh buffer handle read back via `sa_fmt_buffer_data/len`.

// JS `String.prototype.toUpperCase`: ASCII a-z folds to A-Z, rest passes
// through. Fresh buffer handle, same read-back protocol as lower.

// JS `parseFloat` (also serves `Number(s)` float paths and the global
// `parseFloat`): leading ASCII whitespace skipped, optional sign,
// `Infinity`/`NaN` (sign applies to Infinity only), decimal with optional
// fraction/exponent; trailing garbage ignored; no digits at all yields
// quiet NaN; overflow yields signed infinity.
pub export fn sa_parse_float(ptr: ?[*]const u8, len: u64) f64 {
    const bytes = constBytes(ptr, len) catch return std.math.nan(f64);
    var i: usize = 0;
    while (i < bytes.len and isAsciiWhitespace(bytes[i])) : (i += 1) {}
    var negative = false;
    if (i < bytes.len and (bytes[i] == '+' or bytes[i] == '-')) {
        negative = bytes[i] == '-';
        i += 1;
    }
    const rest = bytes[i..];
    if (rest.len >= 8 and std.mem.eql(u8, rest[0..8], "Infinity")) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    if (rest.len >= 3 and std.mem.eql(u8, rest[0..3], "NaN")) return std.math.nan(f64);
    // Scan the maximal decimal prefix: digits[.digits][(e|E)[+-]digits],
    // requiring at least one digit on either side of the dot.
    var j: usize = 0;
    while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    const int_digits = j;
    if (j < rest.len and rest[j] == '.') {
        j += 1;
        while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    }
    const frac_digits = j - int_digits - @as(usize, if (j > int_digits and rest[int_digits] == '.') 1 else 0);
    if (int_digits == 0 and frac_digits == 0) return std.math.nan(f64);
    var k: usize = j;
    if (k < rest.len and (rest[k] == 'e' or rest[k] == 'E')) {
        var m: usize = k + 1;
        if (m < rest.len and (rest[m] == '+' or rest[m] == '-')) m += 1;
        const exp_start = m;
        while (m < rest.len and rest[m] >= '0' and rest[m] <= '9') : (m += 1) {}
        if (m > exp_start) k = m;
    }
    const num = std.fmt.parseFloat(f64, rest[0..k]) catch |err| {
        if (err == error.Overflow) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
        return std.math.nan(f64);
    };
    // parseFloat scanned an unsigned prefix; apply the leading sign here
    // (a second negation of an explicitly signed prefix cannot occur:
    // the scan above never consumes '+'/'-').
    return if (negative) -num else num;
}

// JS `String.prototype.repeat`: `bytes` concatenated `count` times.
// `count == 0` yields an empty handle; size overflow yields 0
// (OOM-equivalent). Fresh buffer handle, concat read-back protocol.

/// Shared pad filler: `pad` bytes tiled/truncated to exactly `fill` bytes.
pub fn tilePad(owned: []u8, pad: []const u8) void {
    var i: usize = 0;
    while (i < owned.len) {
        const n = @min(pad.len, owned.len - i);
        std.mem.copyForwards(u8, owned[i..][0..n], pad[0..n]);
        i += n;
    }
}

// JS `String.prototype.padStart`: left-pad with tiled `pad` to
// `target_len` bytes. Shorter-or-equal input and empty `pad` return an
// unchanged copy (JS no-op shape). Fresh buffer handle.

// JS `String.prototype.padEnd`: mirror of padStart on the right.

// JS `String.prototype.replace` / `replaceAll` with a string pattern
// (regex forms are refused at the frontend): `all == 0` swaps the first
// occurrence, nonzero swaps all non-overlapping occurrences. Empty needle
// inserts at 0 (first) or interleaves (all), per JS. Needle absent (or
// longer than hay) returns an unchanged copy. Fresh buffer handle.

// JS `String.prototype.charCodeAt` over the subset's byte-oriented
// strings: the byte at `idx` (0-255). Out of bounds yields -1: JS NaN is
// unrepresentable in i32, and -1 is the subset's OOB sentinel (cf.
// indexOf). The reference frontend's primary path is an inline unchecked
// byte load; this checked primitive is the shared out-of-line shape.

/// JS `String.fromCodePoint`: UTF-8 encoding of one scalar value.
/// Out-of-range codes (negative, > 0x10FFFF, surrogate halves) yield the
/// U+FFFD replacement bytes: the subset has no exceptions, and a specified
/// replacement beats a silent wrong encoding. Fresh buffer handle.



pub fn utf8ScalarAt(bytes: []const u8, index: usize) !struct { scalar: u32, width: usize } {
    if (index >= bytes.len) return error.FileNotFound;
    const b0 = bytes[index];
    if (b0 < 0x80) return .{ .scalar = b0, .width = 1 };

    const width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return error.InvalidArgument;
    if (index + width > bytes.len) return error.InvalidArgument;

    const b1 = bytes[index + 1];
    if (b1 < 0x80 or b1 > 0xbf) return error.InvalidArgument;
    if (width == 2) return .{ .scalar = ((@as(u32, b0) & 0x1f) << 6) | (@as(u32, b1) & 0x3f), .width = 2 };

    const b2 = bytes[index + 2];
    if (b2 < 0x80 or b2 > 0xbf) return error.InvalidArgument;
    if (width == 3) {
        if (b0 == 0xe0 and b1 < 0xa0) return error.InvalidArgument;
        if (b0 == 0xed and b1 >= 0xa0) return error.InvalidArgument;
        return .{ .scalar = ((@as(u32, b0) & 0x0f) << 12) | ((@as(u32, b1) & 0x3f) << 6) | (@as(u32, b2) & 0x3f), .width = 3 };
    }

    const b3 = bytes[index + 3];
    if (b3 < 0x80 or b3 > 0xbf) return error.InvalidArgument;
    if (b0 == 0xf0 and b1 < 0x90) return error.InvalidArgument;
    if (b0 == 0xf4 and b1 >= 0x90) return error.InvalidArgument;
    return .{ .scalar = ((@as(u32, b0) & 0x07) << 18) | ((@as(u32, b1) & 0x3f) << 12) | ((@as(u32, b2) & 0x3f) << 6) | (@as(u32, b3) & 0x3f), .width = 4 };
}

pub fn utf8LossyInvalidWidth(bytes: []const u8, index: usize) usize {
    const b0 = bytes[index];
    const expected_width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return 1;
    var width: usize = 1;
    while (width < expected_width and index + width < bytes.len) : (width += 1) {
        const byte = bytes[index + width];
        if (byte < 0x80 or byte > 0xbf) break;
    }
    return width;
}

pub fn utf8CharRangeAt(bytes: []const u8, char_index: u64) !struct { start: usize, len: usize, scalar: u32 } {
    var byte_index: usize = 0;
    var current: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = try utf8ScalarAt(bytes, byte_index);
        if (current == char_index) return .{ .start = byte_index, .len = decoded.width, .scalar = decoded.scalar };
        byte_index += decoded.width;
        current += 1;
    }
    return error.FileNotFound;
}







pub fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}







// Raw free for SA `alloc` blocks (the native emitter lowers `alloc` to
// libc malloc). SA-level code that must release a heap block through a
// real call -- e.g. sa_vec_free, whose `!` releases the emitter may
// lower to bookkeeping only -- goes through this export instead.
pub export fn sa_mem_free(ptr: ?*anyopaque) void {
    if (comptime is_wasm) return;
    if (ptr) |p| std.c.free(p);
}

pub export fn sa_print_bytes(msg: ?[*]const u8, len: u64) void {
    _ = sa_std_print(msg, len);
}









pub fn tcpConnectTimeoutMs(timeout_ns: u64) !i32 {
    if (timeout_ns == 0) return error.InvalidArgument;
    const whole_ms = timeout_ns / std.time.ns_per_ms;
    const rounded_ms = whole_ms + @intFromBool(timeout_ns % std.time.ns_per_ms != 0);
    return std.math.cast(i32, rounded_ms) orelse error.InvalidArgument;
}





// Unix domain socket support. Streams and listeners reuse the existing
// tcp_stream / tcp_listener resource kinds so read/write/peek/shutdown/close
// and accept all flow through the same sa_std_net_tcp_* paths.















































// ---- TLS/network fingerprint primitives (JA3 / JA4) ----
//
// SA programs building outbound-request fingerprints (mirroring Go's utls /
// CLIProxyAPI / sub2api) need the hashing primitives that JA3 and JA4 are
// defined in terms of: JA3 is md5(ja3_string); JA4's `b`/`c` segments are the
// first 12 hex chars of sha256(sorted-comma-joined list). SA-ASM has no crypto,
// so these are exposed here. They are pure functions over caller-provided bytes
// — no sockets, no allocation beyond the caller's output buffer.

pub fn writeHexLower(dst: []u8, bytes: []const u8) void {
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        dst[i * 2] = hex[bytes[i] >> 4];
        dst[i * 2 + 1] = hex[bytes[i] & 0x0f];
    }
}

// md5 of the input, written as 32 lowercase hex chars into out (cap must be >= 32).
// This is exactly the JA3 hash given a pre-built JA3 string.

// sha256 of the input, written as 64 lowercase hex chars into out (cap must be >= 64).

// JA4 truncated hash: first 12 lowercase hex chars of sha256(input). JA4's `b`
// (cipher) and `c` (extension+sigalg) segments are defined as sha256 truncated
// to 12 hex chars. An all-zero / empty input segment conventionally maps to the
// literal "000000000000", which the caller can special-case; this returns the
// real truncated digest.

// HMAC-SHA-256 (RFC 2104, vectors in RFC 4231) of msg under key, written
// as 64 lowercase hex chars into out (cap must be >= 64). Same status
// model as sa_std_net_sha256_hex.
pub export fn sa_hmac_sha256_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 64) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&digest, msg, key);
    writeHexLower(out[0..64], digest[0..]);
    len_slot.* = 64;
    return finish(SA_STD_OK);
}

// HMAC-SHA-1 (RFC 2104, vectors in RFC 2202) of msg under key, written
// as 40 lowercase hex chars into out (cap must be >= 40).
pub export fn sa_hmac_sha1_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 40) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [20]u8 = undefined;
    std.crypto.auth.hmac.HmacSha1.create(&digest, msg, key);
    writeHexLower(out[0..40], digest[0..]);
    len_slot.* = 40;
    return finish(SA_STD_OK);
}

// Fill the caller buffer with bytes from the OS CSPRNG (the same source
// behind cryptoRandomU64 and sa_deno_random_uuid). A zero length is a
// no-op success, including with a null pointer.
pub export fn sa_crypto_random_bytes(out_ptr: ?[*]u8, len: u64) i32 {
    if (len == 0) return finish(SA_STD_OK);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const n = lenAsUsize(len) catch |err| return finishErr(err);
    sio.io().random(out[0..n]);
    return finish(SA_STD_OK);
}

pub fn expectTimeoutRoundedUpWithin(requested_ns: u64, observed_ns: u64) !void {
    try std.testing.expect(observed_ns >= requested_ns);
    try std.testing.expect(observed_ns - requested_ns <= 10 * std.time.ns_per_ms);
}































