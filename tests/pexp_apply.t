  $ cat > input.ml << EOF
  > let pstr_value_binding = [%melange_only Webapi.Dom.getElementById "foo"]
  > let make () =
  >   let%melange_only pstr_value_binding_2 = Webapi.Dom.getElementById "foo" in
  >   ()
  > 
  > EOF

With the melange compilation-mode cookie everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let pstr_value_binding = Webapi.Dom.getElementById "foo"
  
  let make () =
    let pstr_value_binding_2 = Webapi.Dom.getElementById "foo" in
    ()

Without the cookie, the compilation to native errors out indicating that a function must be used

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let pstr_value_binding =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  
  let make () =
    let pstr_value_binding_2 =
      [%ocaml.error
        "[ppx_platform] melange_only works on function definitions. For other \
         cases, use switch%platform or feel free to open an issue in \
         https://github.com/ml-in-barcelona/ppx_platform."]
    in
    ()
