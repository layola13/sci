# SA-ASM EBNF

This grammar reflects the current repository surface. Features such as `#mode compact`, `@const`, `ptr_add`, and atomics remain deferred, while `stack_alloc` is now supported.

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

inst           = alloc | load | store | borrow | move | release | op | jmp | br | br_null | call | call_indirect | return | take | raw_cast | assume_safe | assume_borrow ;

alloc          = ident "=" "alloc" expr ;
load           = ident "=" "load" ident "+" expr [ "as" type ] ;
store          = "store" ident "+" expr "," operand [ "as" type ] ;
borrow         = ident "=" "&" [ "mut" ] ident ;
move           = "^" ident ;
release        = "!" ident ;
take           = ident "=" "take" ident "+" expr ;
raw_cast       = ident "=" "*" ident ;
assume_safe    = ident "=" "assume_safe" ident ;
assume_borrow  = ident "=" "assume_borrow" ident [ "," "mut" ] ;
op             = ident "=" opcode operand "," operand ;
jmp            = "jmp" ident ;
br             = "br" operand "->" ident "," ident ;
br_null        = "br_null" ident "->" ident "," ident ;
call           = [ ident "=" ] "call" [ "@" ] ident "(" [ arg_list ] ")" ;
call_indirect  = [ ident "=" ] "call_indirect" ident "(" [ arg_list ] ")" ;
return         = "return" [ operand ] ;

param_list     = param { "," param } ;
params         = param { "," param } ;
param          = [ "&" | "^" | "*" ] ident ":" type ;
arg_list       = arg { "," arg } ;
arg            = [ "&" | "^" | "*" ] operand ;
operand        = ident | literal ;

type           = "void" | "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64" | "f32" | "f64" | "ptr" ;
opcode         = "add" | "sub" | "mul" | "div" | "gt" | "lt" | "eq" | "ne" | "and" | "or" | "shl" | "shr" ;
expr           = { any } ;
literal        = { any-but-whitespace } ;
ident          = letter { letter | digit | "_" } ;
integer        = digit { digit } ;
```

Notes:

- The parser is intentionally line-oriented and does not build an AST.
- `build-exe` and `build-wasm` reuse the Zig-backed LLVM path in v0.1.
- Structured `#loc`, `@const`, atomics, and `#mode compact` remain post-v0.1 work. `stack_alloc` is supported.
