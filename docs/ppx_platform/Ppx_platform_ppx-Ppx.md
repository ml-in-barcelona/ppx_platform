
# Module `Ppx_platform_ppx.Ppx`

```ocaml
module Builder = Ppxlib.Ast_builder.Default
```
```ocaml
type target = 
  | Native
  | Js
```
```ocaml
val mode : target Stdlib.ref
```
```ocaml
val melange_only : string
```
```ocaml
val native_only : string
```
```ocaml
val is_platform_tag : Stdlib.String.t -> bool
```
```ocaml
val removed_cases : (string * string) list
```
```ocaml
val removed_message : removed:string -> replacement:string -> string
```
```ocaml
module Platform : sig ... end
```
```ocaml
val remove_type_constraint : Ppxlib.pattern -> Ppxlib.pattern
```
```ocaml
val last_expr_to_raise_melange_only : 
  loc:Ppxlib__.Location.t ->
  string ->
  Ppxlib.expression ->
  Ppxlib__.Import.expression
```
```ocaml
module Melange_only : sig ... end
```
```ocaml
module Preprocess : sig ... end
```
```ocaml
module Removed : sig ... end
```