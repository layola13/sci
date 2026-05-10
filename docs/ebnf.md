# SA-ASM EBNF

This file is the executable grammar companion for the SA-ASM design.

```ebnf
program        = { toplevel } ;
toplevel       = def | macro_def | func_def ;
def            = "#def" IDENT "=" LITERAL ;
macro_def      = "[MACRO]" IDENT macro_params { line } "[END_MACRO]" ;
macro_params   = { "%p" DIGIT } ;
func_def       = "@" IDENT "(" [ param_list ] ")" [ "->" [ "^" ] type ] ":" { line } ;
param_list     = param { "," param } ;
param          = [ "&" | "^" ] IDENT ":" type ;
type           = "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64" | "f32" | "f64" | "ptr" ;
line           = label | inst | native ;
label          = "L_" IDENT ":" ;
inst           = alloc_inst | load_inst | store_inst | op_inst | jmp_inst | br_inst | call_inst | return_inst | take_inst | release_inst | move_inst | borrow_inst ;
alloc_inst     = IDENT "=" "alloc" LITERAL ;
load_inst      = IDENT "=" "load" IDENT "+" LITERAL [ "as" type ] ;
store_inst     = "store" IDENT "+" LITERAL "," operand [ "as" type ] ;
op_inst        = IDENT "=" OP operand "," operand ;
jmp_inst       = "jmp" "L_" IDENT ;
br_inst        = "br" operand "->" "L_" IDENT "," "L_" IDENT ;
br_null        = "br_null" IDENT "->" "L_" IDENT "," "L_" IDENT ;
call_inst      = [ IDENT "=" ] "call" "@" IDENT "(" [ arg_list ] ")" ;
call_indirect  = [ IDENT "=" ] "call_indirect" IDENT "(" [ arg_list ] ")" ;
arg_list       = arg { "," arg } ;
arg            = [ "&" | "^" ] IDENT | LITERAL ;
return_inst    = "return" [ IDENT ] ;
take_inst      = IDENT "=" "take" IDENT "+" LITERAL ;
release_inst   = "!" IDENT ;
move_inst      = "^" IDENT ;
borrow_inst    = IDENT "=" "&" [ "mut" ] IDENT ;
native         = "$" ANY_TEXT "$" ;
expand         = "EXPAND" IDENT arg_list ;
rep_block      = "[REP" LITERAL "]" { line } "[END_REP]" ;
OP             = "add" | "sub" | "mul" | "div" | "gt" | "lt" | "eq" | "ne" | "and" | "or" | "shl" | "shr" ;
```
