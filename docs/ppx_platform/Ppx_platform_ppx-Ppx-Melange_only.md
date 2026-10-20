
# Module `Ppx.Melange_only`

```ocaml
val get_function_name : Ppxlib.pattern_desc -> string
```
```ocaml
val error_only_works_on : loc:Ppxlib.location -> Ppxlib_ast.Ast.expression
```
```ocaml
val remove_alert_only : loc:Ppxlib__.Location.t -> Ppxlib__.Import.attribute
```
```ocaml
val melange_only_fun : 
  loc:Ppxlib__.Location.t ->
  Ppxlib__.Import.arg_label ->
  Ppxlib__.Import.pattern ->
  Astlib__.Ast_502.Parsetree.expression ->
  Ppxlib__.Import.expression
```
```ocaml
val melange_only_value_binding : 
  Ppxlib.pattern ->
  Ppxlib.expression ->
  Ppxlib__.Import.value_binding
```
```ocaml
val extractor_single_payload : 
  (Ppxlib__.Import.payload,
    Ppxlib__.Import.expression ->
    Ppxlib__.Import.expression,
    Ppxlib__.Import.expression)
    Ppxlib.Ast_pattern.t
```
```ocaml
val expression_handler : 
  ctxt:Ppxlib.Expansion_context.Extension.t ->
  Ppxlib.expression ->
  Ppxlib.expression
```
```ocaml
val expression_rule : Ppxlib.Context_free.Rule.t
```
```ocaml
val make_vb_with_melange_only : 
  loc:Ppxlib__.Location.t ->
  ?type_constraint:Ppxlib.core_type ->
  Ppxlib__.Import.pattern ->
  Ppxlib.expression ->
  Ppxlib_ast.Ast.structure_item
```
```ocaml
val extractor_vb : 
  (Ppxlib__.Import.payload,
    Ppxlib__.Import.rec_flag ->
    Ppxlib__.Import.pattern ->
    Ppxlib__.Import.expression ->
    Ppxlib__.Import.structure_item,
    Ppxlib__.Import.structure_item)
    Ppxlib__.Ast_pattern0.t
```
```ocaml
val structure_item_handler : 
  ctxt:Ppxlib.Expansion_context.Extension.t ->
  Ppxlib.rec_flag ->
  Ppxlib_ast.Ast.pattern ->
  Ppxlib_ast.Ast.expression ->
  Ppxlib_ast.Ast.structure_item
```
```ocaml
val structure_item_rule : Ppxlib.Context_free.Rule.t
```
```ocaml
val rules : Ppxlib.Context_free.Rule.t list
```