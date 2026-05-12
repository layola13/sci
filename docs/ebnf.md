# SA-ASM EBNF

This grammar reflects the current repository surface. The v0.1 implementation is
line-oriented, does not build an AST, and now includes `stack_alloc`, `?` early
return, `panic_msg`, and atomic forms. `@const` and `ptr_add` remain outside the
current parser surface.

```ebnf
program        = { line } ;
line           = blank | comment | def | macro_start | macro_end | rep_start | rep_end | expand | func_decl | ffi_decl | extern_decl | export_decl | label | inst | native ;

blank          = "" ;
comment        = "//" { any } ;
def            = "#def" ident "=" expr ;

macro_start    = "[MACRO]" ident [ param_list ] ;
macro_end      = "[END_MACRO]" ;
rep_start      = "[REP" integer "]" ;
rep_end        = "[END_REP]" ;
expand         = "EXPAND" ident [ arg_list ] ;

func_decl      = "@" ident "(" [ params ] ")" [ "->" type ] ":" ;
ffi_decl       = "@ffi_wrapper" ident "(" [ params ] ")" [ "->" type ] ":" ;
extern_decl    = "@extern" ident "(" [ params ] ")" [ "->" type ] ;
export_decl    = "@export" ident "(" [ params ] ")" [ "->" type ] ":" ;

label          = ident ":" ;
native         = "$" { any } "$" ;

inst           =
    alloc | stack_alloc | load | store | take | borrow | move | release |
    op | jmp | br | br_null | call | call_indirect | try_ | early_return |
    panic | panic_msg | atomic_load | atomic_store | cmpxchg | atomic_rmw |
    fence | raw_cast | assume_safe | assume_borrow ;

alloc          = ident "=" "alloc" expr ;
stack_alloc    = ident "=" "stack_alloc" expr ;
load           = ident "=" "load" ident "+" expr [ "as" type ] ;
store          = "store" ident "+" expr "," operand [ "as" type ] ;
take           = ident "=" "take" ident "+" expr [ "as" type ] ;
borrow         = ident "=" "&" [ "mut" ] ident ;
move           = "^" ident ;
release        = "!" ident ;
op             = ident "=" opcode operand "," operand ;
jmp            = "jmp" ident ;
br             = "br" operand "->" ident "," ident ;
br_null        = "br_null" ident "->" ident "," ident ;
call           = [ ident "=" ] "call" [ "@" ] ident "(" [ arg_list ] ")" ;
call_indirect  = [ ident "=" ] "call_indirect" ident "(" [ arg_list ] ")" ;
try_           = ident "=" "?" ident ;
early_return   = ident "=" "?" ident ;
panic          = "panic" "(" operand ")" ;
panic_msg      = "panic_msg" "(" operand "," operand "," operand ")" ;
atomic_load    = ident "=" "atomic_load" ident "+" expr [ "as" type ] [ ordering ] ;
atomic_store   = "atomic_store" ident "+" expr "," operand [ "as" type ] [ ordering ] ;
cmpxchg        = ident "," ident "=" "cmpxchg" ident "+" expr "," operand "," operand [ "as" type ] [ ordering ] [ ordering ] ;
atomic_rmw     = ident "=" "atomic_rmw_" rmw_op ident "+" expr "," operand [ "as" type ] [ ordering ] ;
fence          = "fence" [ ordering ] ;
raw_cast       = ident "=" "*" ident ;
assume_safe    = ident "=" "assume_safe" ident ;
assume_borrow  = ident "=" "assume_borrow" ident [ "," "mut" ] ;

param_list     = param { "," param } ;
params         = param { "," param } ;
param          = [ "&" | "^" | "*" ] ident ":" type ;
arg_list       = arg { "," arg } ;
arg            = [ "&" | "^" | "*" ] operand ;
operand        = ident | literal ;

type           = "void" | "i1" | "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64" | "f32" | "f64" | "ptr" ;
opcode         = "add" | "sub" | "mul" | "div" | "gt" | "lt" | "eq" | "ne" | "and" | "or" | "shl" | "shr" ;
rmw_op         = "add" | "sub" | "and" | "or" | "xor" | "xchg" | "min" | "max" | "smin" | "smax" | "umin" | "umax" ;
ordering       = "relaxed" | "acquire" | "release" | "acq_rel" | "seq_cst" ;
expr           = { any } ;
literal        = { any-but-whitespace } ;
ident          = letter { letter | digit | "_" } ;
integer        = digit { digit } ;
```

Notes:

- The parser is intentionally line-oriented and does not build an AST.
- `build-exe` and `build-wasm` reuse the Zig-backed LLVM path in v0.1.
- `@const`, `ptr_add`, `#mode compact`, and the post-v0.1 WASM emitter remain
  deferred.
