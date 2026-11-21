//! sa_std YAML: parser + dotted-path accessors + builder/serializer
//! (STD batch 4; demand source: the sub2api / new-api backend censuses
//! of 2026-10-28 -- both gateways use YAML as a primary config format
//! while sa_std shipped only JSON and TOML faces).
//!
//! The face mirrors sa_toml.zig: parse the whole text into an opaque
//! OWNED U64 HANDLE (not a pointer), then read values by dotted path
//! ("server.port"); array elements in a path are addressed by a
//! numeric segment ("upstreams.0.host"). Status codes mirror
//! sa_std.zig (0 ok, 1 invalid argument, 2 invalid handle, 3 not
//! found, 5 no memory). Parse failures return handle 0 and are
//! reported through sa_yaml_last_error with a line/column position.
//!
//! This is a CONFIG-LEVEL SUBSET of YAML 1.2, not a general YAML
//! processor. The subset rulings (also in sa_std/encoding/yaml.sai):
//!  - Block mappings/sequences by indentation, flow mappings and
//!    sequences, plain / single-quoted / double-quoted scalars,
//!    literal (|) and folded (>) block scalars with chomping and
//!    indent indicators, comments, multi-document streams (--- / ...),
//!    %YAML directives (1.x; %TAG and unknown directives are
//!    UNSUPPORTED), anchors (&a), aliases (*a, deep-copied on use)
//!    and merge keys (<<).
//!  - Plain-scalar type resolution is aligned with JSON, NOT with
//!    YAML 1.1: null is ~ / null / Null / NULL / empty; bool is
//!    true/false in the three core-schema casings ONLY (yes/no/on/off
//!    stay strings); integers are decimal (underscores between digits
//!    allowed), 0x hex, 0o and legacy 0NNN octal, 0b binary; floats
//!    need a dot or an exponent, plus .inf/.nan; timestamps and
//!    sexagesimal numbers stay strings. An integer that overflows i64
//!    becomes a float (magnitude preserved approximately). Quoted and
//!    block scalars are always strings. Mapping keys are stored as
//!    their scalar text (quoted keys unescaped): the DOM is a
//!    string-keyed tree exactly like JSON/TOML, which is what makes
//!    sa_yaml_to_json a pure walk.
//!  - Duplicate keys in one mapping are a hard parse error (never
//!    silently last-wins), reported with the duplicate's position.
//!  - Explicit tags (!!str, !custom, ...), complex/explicit keys
//!    ("? key"), and document markers not at column 0 as content are
//!    rejected with an explicit UNSUPPORTED error -- nothing in this
//!    module silently approximates a construct it does not implement.
//!    Document markers ARE recognized at column 0 before parsing
//!    (subset simplification), so a column-0 "---" line can never be
//!    block-scalar content.
//!
//! Documents own an arena: every string/subtree a parse or an alias
//! clone produces lives in the arena and is released by sa_yaml_free.
//! The stringify / to_json buffers are document-owned (allocated
//! outside the arena) and are invalidated by the next mutation or
//! the next call of the same emitter on that document.

const std = @import("std");
const sio = @import("sio");

const _y01 = @import("sa_yaml/y01.zig");
const _y02 = @import("sa_yaml/y02.zig");
const _y03 = @import("sa_yaml/y03.zig");
const _y04 = @import("sa_yaml/y04.zig");
const _y05 = @import("sa_yaml/y05.zig");
const _y06 = @import("sa_yaml/y06.zig");

pub const KIND_UNDEFINED = @import("sa_yaml/y01.zig").KIND_UNDEFINED; pub const KIND_NULL = @import("sa_yaml/y01.zig").KIND_NULL; pub const KIND_BOOL = @import("sa_yaml/y01.zig").KIND_BOOL;
pub const KIND_INTEGER = @import("sa_yaml/y01.zig").KIND_INTEGER; pub const KIND_FLOAT = @import("sa_yaml/y01.zig").KIND_FLOAT; pub const KIND_STRING = @import("sa_yaml/y01.zig").KIND_STRING;
pub const KIND_ARRAY = @import("sa_yaml/y01.zig").KIND_ARRAY; pub const KIND_TABLE = @import("sa_yaml/y01.zig").KIND_TABLE; pub const sa_yaml_parse = @import("sa_yaml/y04.zig").sa_yaml_parse;
pub const sa_yaml_parse_at = @import("sa_yaml/y04.zig").sa_yaml_parse_at; pub const sa_yaml_count_documents = @import("sa_yaml/y04.zig").sa_yaml_count_documents;
pub const sa_yaml_free = @import("sa_yaml/y04.zig").sa_yaml_free; pub const sa_yaml_last_error = @import("sa_yaml/y04.zig").sa_yaml_last_error;
pub const sa_yaml_kind = @import("sa_yaml/y04.zig").sa_yaml_kind; pub const sa_yaml_get_string = @import("sa_yaml/y04.zig").sa_yaml_get_string;
pub const sa_yaml_get_i64 = @import("sa_yaml/y04.zig").sa_yaml_get_i64; pub const sa_yaml_get_f64 = @import("sa_yaml/y04.zig").sa_yaml_get_f64;
pub const sa_yaml_get_bool = @import("sa_yaml/y04.zig").sa_yaml_get_bool; pub const sa_yaml_array_len = @import("sa_yaml/y04.zig").sa_yaml_array_len;
pub const sa_yaml_table_len = @import("sa_yaml/y04.zig").sa_yaml_table_len; pub const sa_yaml_array_get_string = @import("sa_yaml/y04.zig").sa_yaml_array_get_string;
pub const sa_yaml_array_get_i64 = @import("sa_yaml/y04.zig").sa_yaml_array_get_i64; pub const sa_yaml_table_key_at = @import("sa_yaml/y05.zig").sa_yaml_table_key_at;
pub const sa_yaml_new = @import("sa_yaml/y05.zig").sa_yaml_new; pub const sa_yaml_set_string = @import("sa_yaml/y05.zig").sa_yaml_set_string;
pub const sa_yaml_set_i64 = @import("sa_yaml/y05.zig").sa_yaml_set_i64; pub const sa_yaml_set_f64 = @import("sa_yaml/y05.zig").sa_yaml_set_f64;
pub const sa_yaml_set_bool = @import("sa_yaml/y05.zig").sa_yaml_set_bool; pub const sa_yaml_set_null = @import("sa_yaml/y05.zig").sa_yaml_set_null;
pub const sa_yaml_set_table = @import("sa_yaml/y05.zig").sa_yaml_set_table; pub const sa_yaml_remove = @import("sa_yaml/y05.zig").sa_yaml_remove;
pub const sa_yaml_array_push_string = @import("sa_yaml/y05.zig").sa_yaml_array_push_string; pub const sa_yaml_array_push_i64 = @import("sa_yaml/y05.zig").sa_yaml_array_push_i64;
pub const sa_yaml_array_push_f64 = @import("sa_yaml/y05.zig").sa_yaml_array_push_f64; pub const sa_yaml_array_push_bool = @import("sa_yaml/y05.zig").sa_yaml_array_push_bool;
pub const sa_yaml_array_push_null = @import("sa_yaml/y05.zig").sa_yaml_array_push_null; pub const sa_yaml_array_push_table = @import("sa_yaml/y05.zig").sa_yaml_array_push_table;
pub const sa_yaml_stringify = @import("sa_yaml/y05.zig").sa_yaml_stringify; pub const sa_yaml_to_json = @import("sa_yaml/y05.zig").sa_yaml_to_json;
