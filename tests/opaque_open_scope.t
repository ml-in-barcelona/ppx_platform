On Native, an open of a module the ppx cannot see into may shadow any name in
scope. Ext stands for a library with a different Native and Melange build, so
the ignores emitted for discarded code must not resolve through that open.

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
  > EOF

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl > native/input.ml
  $ cat native/input.ml
  module M = struct
    let x = 1
  end
  
  let match_let_open () =
    let open Ext in
    ()
  
  let melange_only_let_open () =
    let open Ext in
    let g () = Ppx_platform.fail_melange_only "g" [@@alert "-melange_only"] in
    ignore g
  
  let match_local_open () =
    let open Ext in
    ()
  
  let melange_only_local_open () =
    let open Ext in
    let g () = Ppx_platform.fail_melange_only "g" [@@alert "-melange_only"] in
    ignore g
  
  let bound_after_open () =
    let open Ext in
    let z = 1 in
    let _ = z in
    ()
  
  class c =
    let open Ext in
    object
      method f = ()
    end
  
  module Top_open = struct
    open Ext
  
    let f () = ()
  
    let (g
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     (fun () -> Ppx_platform.fail_melange_only "g") [@alert "-melange_only"]
    [@@warning "-32"]
  end
  
  module Top_include = struct
    include Ext
  
    let f () = ()
  
    let (g
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     (fun () -> Ppx_platform.fail_melange_only "g") [@alert "-melange_only"]
    [@@warning "-32"]
  end
  $ ocamlc -c -w +A-33-44-45-70 -alert @melange_only -I native native/input.ml

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/input.ml
  $ ocamlc -c -w +A-44-45-70 -alert -melange_only -I js js/input.ml
