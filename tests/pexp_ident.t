  $ cat > input.ml << EOF
  > let make () =
  >   let%melange_only pexp_ident = Webapi__Dom__Element.asHtmlElement in
  >   ()
  > EOF

With -js flag everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let make () =
    let pexp_ident = Webapi__Dom__Element.asHtmlElement in
    ()

Without -js flag, a binding to an identifier becomes a function that raises, as at the top level

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let make () =
    let (pexp_ident
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ -> Ppx_platform.fail_melange_only "pexp_ident"
       [@@alert "-melange_only"]
    in
    ()
