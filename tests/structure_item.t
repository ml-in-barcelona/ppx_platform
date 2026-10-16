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
  $ cat $INSIDE_DUNE/runtime/ppx_platform.ml >> output.ml
  $ echo "end" >> output.ml
  $ ocamlc -c output.ml
