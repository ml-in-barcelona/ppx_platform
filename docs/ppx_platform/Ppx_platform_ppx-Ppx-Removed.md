
# Module `Ppx.Removed`

```ocaml
val extension_rule : 
  'a Ppxlib__Extension.Context.t ->
  error:(loc:Ppxlib__.Location.t -> string -> 'a) ->
  Ppxlib.Context_free.Rule.t
```
```ocaml
val rules : Ppxlib.Context_free.Rule.t list
```
```ocaml
val attribute_replacement : Ppxlib.attribute -> (string * string) option
```
```ocaml
val reject : Ppxlib.Ast_traverse.iter
```