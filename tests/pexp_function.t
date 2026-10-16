  $ cat > input.re << EOF
  > let%melange_only foo = fun
  >     | x when x < 0. => None
  >     | x => Some("bar");
  > 
  > let make = () => {
  >   let%melange_only foo = fun
  >     | x when x < 0. => None
  >     | x => Some("bar");
  >   ();
  > };
  > EOF

  $ refmt --parse re --print ml input.re > input.ml

With -js flag everything keeps as it is and melange_only extension disappears

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let foo = function x when x < 0. -> None | x -> Some "bar" [@explicit_arity]
  
  let make () =
    let foo = function
      | x when x < 0. -> None
      | x -> ( Some "bar" [@explicit_arity])
    in
    ()

Without -js flag, the compilation to native errors out indicating that a function must be used

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let (foo
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun _ ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "foo")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let make () =
    let foo =
      [%ocaml.error
        "[ppx_platform] melange_only works on function definitions. For other \
         cases, use switch%platform or feel free to open an issue in \
         https://github.com/ml-in-barcelona/ppx_platform."]
    in
    ()
