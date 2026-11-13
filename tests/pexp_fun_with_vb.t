  $ cat > input.ml << EOF
  > let make () =
  >   let%melange_only fun_value_binding_pexp_fun_2arg evt moar_arguments =
  >     let a = "foo" in
  >     Webapi.Dom.getElementById a
  >   in
  > 
  >   let%melange_only fun_value_binding_pexp_fun_default_expr ?(evt=22) =
  >     Webapi.Dom.getElementById evt
  >   in
  > 
  >   let%melange_only fun_value_binding_pexp_fun_2arg evt moar_arguments =
  >     let a = 1 in
  >     let b = 2 in
  >     Webapi.Dom.getElementById b
  >   in
  >   ()
  > 
  > EOF

With the melange compilation-mode cookie everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let make () =
    let fun_value_binding_pexp_fun_2arg evt moar_arguments =
      let a = "foo" in
      Webapi.Dom.getElementById a
    in
    let fun_value_binding_pexp_fun_default_expr ?(evt = 22) =
      Webapi.Dom.getElementById evt
    in
    let fun_value_binding_pexp_fun_2arg evt moar_arguments =
      let a = 1 in
      let b = 2 in
      Webapi.Dom.getElementById b
    in
    ()

Without the cookie, the compilation to native replaces the expression with a raise

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl > output.ml

  $ cat output.ml
  let make () =
    let fun_value_binding_pexp_fun_2arg evt =
      Ppx_platform.fail_melange_only "fun_value_binding_pexp_fun_2arg"
        [@@alert "-melange_only"]
    in
    let fun_value_binding_pexp_fun_default_expr ?evt =
      Ppx_platform.fail_melange_only "fun_value_binding_pexp_fun_default_expr"
        [@@alert "-melange_only"]
    in
    let fun_value_binding_pexp_fun_2arg evt =
      Ppx_platform.fail_melange_only "fun_value_binding_pexp_fun_2arg"
        [@@alert "-melange_only"]
    in
    ()

Replace Ppx_platform.fail_melange_only with print_endline so ocamlc can compile it without the runtime library dependency
  $ sed "s/Ppx_platform.fail_melange_only/print_endline/g" output.ml > output.ml

  $ ocamlc -c output.ml
