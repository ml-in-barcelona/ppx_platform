On Native, an open of a module the ppx cannot see into may shadow any name in
scope. Ext stands for a library with a different Native and Melange build. Only
names bound locally in the enclosing expression get an ignore, so no ignore
names a module path, a top-level value, or a name that comes from an open.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

  $ mkdir native js
  $ echo 'module M = struct let y = 2 end' > native/ext.ml
  $ echo 'module M = struct let x = 3 end' > js/ext.ml
  $ ocamlc -c native/ext.ml
  $ ocamlc -c js/ext.ml

  $ cat > input.ml << 'EOF'
  > module M = struct let x = 1 end
  > 
  > let match_let_open () =
  >   let open Ext in
  >   match%platform () with Native -> () | Melange -> ignore M.x
  > 
  > let melange_only_let_open () =
  >   let open Ext in
  >   let%melange_only g () = M.x in
  >   ignore g
  > 
  > let match_local_open () =
  >   Ext.(match%platform () with Native -> () | Melange -> ignore M.x)
  > 
  > let melange_only_local_open () =
  >   Ext.(
  >     let%melange_only g () = M.x in
  >     ignore g)
  > 
  > let bound_after_open () =
  >   let open Ext in
  >   let z = 1 in
  >   match%platform () with Native -> () | Melange -> ignore (z + M.x)
  > 
  > class c =
  >   let open Ext in
  >   object
  >     method f = match%platform () with Native -> () | Melange -> ignore M.x
  >   end
  > 
  > module Top_open = struct
  >   open Ext
  >   let f () = match%platform () with Native -> () | Melange -> ignore M.x
  >   let%melange_only g () = M.x
  > end
  > 
  > module Top_include = struct
  >   include Ext
  >   let f () = match%platform () with Native -> () | Melange -> ignore M.x
  >   let%melange_only g () = M.x
  > end
  > 
  > module Wrapper = struct
  >   include Ext
  >   let after_inc = 10
  > end
  > 
  > let open_wrapper () =
  >   let open Wrapper in
  >   match%platform () with Native -> () | Melange -> ignore (after_inc + M.x)
  > 
  > let use_wrapper_member () =
  >   match%platform () with Native -> () | Melange -> ignore Wrapper.after_inc
  > 
  > module Wrapper2 = struct
  >   include Wrapper
  >   let more = 20
  > end
  > 
  > let open_wrapper2 () =
  >   let open Wrapper2 in
  >   match%platform () with Native -> () | Melange -> ignore (after_inc + more + M.x)
  > 
  > module Sig_wrapper : sig
  >   include module type of Ext
  >   val extra : int
  > end = struct
  >   include Ext
  >   let extra = 30
  > end
  > 
  > let open_sig_wrapper () =
  >   let open Sig_wrapper in
  >   match%platform () with Native -> () | Melange -> ignore (extra + M.x)
  > 
  > let outer_values_ext_open items =
  >   let limit = 10 in
  >   let open Ext in
  >   match%platform () with Native -> () | Melange -> ignore (items + limit + M.x)
  > 
  > let outer_values_local_open items =
  >   let limit = 10 in
  >   Stdlib.List.(match%platform () with Native -> () | Melange -> ignore (length items + limit))
  > 
  > let outer_values_let_open items =
  >   let limit = 10 in
  >   let open Stdlib.List in
  >   match%platform () with Native -> () | Melange -> ignore (length items + limit)
  > 
  > let outer_values_melange_only items =
  >   let limit = 10 in
  >   let open Stdlib.List in
  >   let%melange_only g () = length items + limit in
  >   ignore g
  > 
  > module List = struct
  >   include Stdlib.List
  >   let second l = nth l 1
  > end
  > 
  > let outer_values_open_ended items =
  >   let limit = 10 in
  >   List.(match%platform () with Native -> () | Melange -> ignore (second items + limit))
  > EOF

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl > native/input.ml
  $ grep -n "let _ = \|let module _" native/input.ml
  26:  let _ = z in
  104:  let _ = items in
  105:  let _ = limit in
  111:  let _ = items in
  112:  let _ = limit in
  118:  let _ = items in
  119:  let _ = limit in
  126:    let _ = items in
  127:    let _ = limit in
  142:  let _ = items in
  143:  let _ = limit in
  $ ocamlc -c -w +A-33-44-45-70 -warn-error +A -alert @melange_only -I native native/input.ml

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/input.ml
  $ ocamlc -c -w +A-44-45-70 -alert -melange_only -I js js/input.ml
