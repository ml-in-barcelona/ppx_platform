  $ cat > input.ml << EOF
  > let make () =
  >   let%melange_only pexp_ident = Webapi__Dom__Element.asHtmlElement in
  >   ()
  > EOF

With the melange compilation-mode cookie everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let make () =
    let pexp_ident = Webapi__Dom__Element.asHtmlElement in
    ()

Without the cookie, the compilation to native errors out indicating that a function must be used

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let make () =
    let pexp_ident =
      [%ocaml.error
        "[ppx_platform] melange_only works on function definitions. For other \
         cases, use switch%platform or feel free to open an issue in \
         https://github.com/ml-in-barcelona/ppx_platform."]
    in
    ()
