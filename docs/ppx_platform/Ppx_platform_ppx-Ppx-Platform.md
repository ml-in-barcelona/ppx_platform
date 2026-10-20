
# Module `Ppx.Platform`

```ocaml
val pattern : ('a, 'a Ppxlib__.Loc.t -> 'b, 'b) Ppxlib.Ast_pattern.t
```
```ocaml
val case_name : Ppxlib.case -> string option
```
```ocaml
val collect_expressions : 
  loc:Ppxlib.location ->
  Ppxlib.case ->
  Ppxlib.case ->
  (Ppxlib.expression * Ppxlib.expression, Ppxlib_ast.Ast.expression)
    Stdlib.result
```
```ocaml
val switch_platform_requires_a_match : 
  loc:Ppxlib.location ->
  Ppxlib_ast.Ast.expression
```
```ocaml
val handler : ctxt:'a -> Ppxlib.payload Ppxlib.loc -> Ppxlib.expression
```
```ocaml
val rule : Ppxlib.Context_free.Rule.t
```