
# Module `Ppx.Preprocess`

```ocaml
val eval_attr : Ppxlib.attribute -> [> `drop | `keep ]
```
```ocaml
val expression_error : 
  loc:Ppxlib.location ->
  Ppxlib.attribute list ->
  Ppxlib_ast.Ast.expression
```
```ocaml
val should_keep : Ppxlib.attribute list -> [> `drop | `keep ]
```
```ocaml
val should_keep_many : 
  'a list ->
  ('a -> Ppxlib.attribute list) ->
  [> `drop | `keep ]
```
```ocaml
val apply_config_on_types : 
  Ppxlib.type_declaration list ->
  Ppxlib.type_declaration list
```
```ocaml
val apply_config_on_structure_item : 
  Ppxlib.structure_item ->
  Ppxlib.structure_item option
```
```ocaml
val apply_config_on_signature_item : 
  Ppxlib.signature_item ->
  Ppxlib.signature_item option
```
```ocaml
val traverse : Ppxlib.Ast_traverse.map
```