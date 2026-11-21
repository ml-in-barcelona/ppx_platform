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

Without -js flag, `function` cases become a stub that takes one argument and raises, at the top level and in a local binding

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let (foo
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun _ -> Ppx_platform.fail_melange_only "foo") [@alert "-melange_only"]
  [@@warning "-32"]
  
  let make () =
    let (foo
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ -> Ppx_platform.fail_melange_only "foo"
       [@@alert "-melange_only"]
    in
    ()
