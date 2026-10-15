With -js flag the Client case is kept

  $ refmt --parse re --print ml input.re > input.re.ml

  $ ../standalone.exe -impl input.re.ml -js | ocamlformat - --enable-outside-detected-project --impl
  doClientSideLogic ();;
  
  let value = doClientSideLogic ()
  let universal_fn () = doClientSideLogic ()
  let universal_fn_with_arg1 arg1 = doClientSideLogic ()

Without -js flag, the compilation to native keeps the Server case.

  $ ../standalone.exe -impl input.re.ml | ocamlformat - --enable-outside-detected-project --impl
  doServerSideLogic ();;
  
  let value = doServerSideLogic ()
  let universal_fn () = doServerSideLogic ()
  let universal_fn_with_arg1 arg1 = doServerSideLogic arg1
