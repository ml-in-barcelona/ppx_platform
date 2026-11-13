  $ cat > input.ml << EOF
  > [%%melange_only let ( let+ ) = fun p f -> map f p]
  > 
  > let%melange_only pexp_ident = Webapi__Dom__Element.asHtmlElement
  > 
  > let%melange_only pexp_fun_1arg_structure_item evt =
  >   Webapi.Dom.getElementById "foo"
  >  
  > let%melange_only pexp_fun_2arg_structure_item evt moar_arguments =
  >   let a = "foo" in
  >   Webapi.Dom.getElementById a
  > 
  > let%melange_only pexp_fun_2arg_structure_item evt moar_arguments =
  >   let a = "foo" in
  >   let a = "foo" in
  >   Webapi.Dom.getElementById a
  > 
  > let%melange_only perform ?abortController ?(base = defaultBase) (req : ('handler, 'a, 'i, 'o) Api.request) input =
  >   Js.log abortController;
  >   Js.log base;
  >   Js.log req;
  >   Js.log input
  > 
  > EOF

With -js flag everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let ( let+ ) p f = map f p
  let pexp_ident = Webapi__Dom__Element.asHtmlElement
  let pexp_fun_1arg_structure_item evt = Webapi.Dom.getElementById "foo"
  
  let pexp_fun_2arg_structure_item evt moar_arguments =
    let a = "foo" in
    Webapi.Dom.getElementById a
  
  let pexp_fun_2arg_structure_item evt moar_arguments =
    let a = "foo" in
    let a = "foo" in
    Webapi.Dom.getElementById a
  
  let perform ?abortController ?(base = defaultBase)
      (req : ('handler, 'a, 'i, 'o) Api.request) input =
    Js.log abortController;
    Js.log base;
    Js.log req;
    Js.log input

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let (( let+ )
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun p -> Ppx_platform.fail_melange_only "let+") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (pexp_ident
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
    Obj.magic () [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (pexp_fun_1arg_structure_item
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun evt ->
    Ppx_platform.fail_melange_only "pexp_fun_1arg_structure_item")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (pexp_fun_2arg_structure_item
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun evt ->
    Ppx_platform.fail_melange_only "pexp_fun_2arg_structure_item")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (pexp_fun_2arg_structure_item
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun evt ->
    Ppx_platform.fail_melange_only "pexp_fun_2arg_structure_item")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (perform
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ?abortController ->
    Ppx_platform.fail_melange_only "perform")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
Replace Ppx_platform.fail_melange_only with print_endline so ocamlc can compile it without the runtime library dependency
  $ echo "module Ppx_platform = struct" >> output.ml
  $ cat $INSIDE_DUNE/src/runtime/ppx_platform.ml >> output.ml
  $ echo "end" >> output.ml
  $ ocamlc -c output.ml

With a type annotation that is an arrow, the native build gets a function built from the type, whatever the body is.
The annotation and the labels stay, so the value matches an interface. Without an arrow annotation the item is
handled as before.

  $ cat > input_annotated.ml << EOF
  > let%melange_only set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]
  > let%melange_only on_key : key:string -> ?repeat:bool -> unit -> unit = [%mel.raw "function (k, r) {}"]
  > let%melange_only is_dev : bool = true
  > EOF

  $ cat > input_annotated_server.mli << EOF
  > val set_title : string -> unit
  > val on_key : key:string -> ?repeat:bool -> unit -> unit
  > val is_dev : bool
  > EOF

  $ ./standalone.exe -impl input_annotated.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let set_title = [%mel.raw "function (t) { document.title = t }"]
  let on_key = [%mel.raw "function (k, r) {}"]
  let is_dev = true

  $ ./standalone.exe -impl input_annotated.ml | ocamlformat - --enable-outside-detected-project --impl
  let ((set_title
        [@alert
          melange_only
            "This value only exists in the Melange build. Use it inside a \
             let%melange_only function, or a Melange branch of match%platform."]) :
        string -> unit) =
   (fun _ -> Ppx_platform.fail_melange_only "set_title") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let ((on_key
        [@alert
          melange_only
            "This value only exists in the Melange build. Use it inside a \
             let%melange_only function, or a Melange branch of match%platform."]) :
        key:string -> ?repeat:bool -> unit -> unit) =
   (fun ~key:_ ?repeat:_ _ ->
    Ppx_platform.fail_melange_only "on_key")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let is_dev = true

  $ cp $INSIDE_DUNE/src/runtime/ppx_platform.ml . && ocamlc -c ppx_platform.ml
  $ ./standalone.exe -impl input_annotated.ml > input_annotated_server.ml && ocamlc -c input_annotated_server.mli input_annotated_server.ml
  File "input_annotated_server.ml", line 1:
  Alert melange_only: set_title
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  File "input_annotated_server.ml", lines 1-3, characters 5-151:
  1 | .....((set_title)[@alert
  2 |                    melange_only
  3 |                      "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform."])
    Definition
  File "input_annotated_server.mli", line 1, characters 0-30:
    Expected signature
  
  File "input_annotated_server.ml", line 1:
  Alert melange_only: on_key
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  File "input_annotated_server.ml", lines 7-9, characters 5-148:
  7 | .....((on_key)[@alert
  8 |                 melange_only
  9 |                   "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform."])
    Definition
  File "input_annotated_server.mli", line 2, characters 0-55:
    Expected signature
