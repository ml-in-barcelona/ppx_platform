With the melange compilation-mode cookie the Melange case is kept

  $ refmt --parse re --print ml input.re > input.re.ml

  $ ../standalone.exe -impl input.re.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  doMelangeLogic ();;
  
  let value = doMelangeLogic ()
  let universal_fn () = doMelangeLogic ()
  let universal_fn_with_arg1 arg1 = doMelangeLogic ()

Without the cookie, the compilation to native keeps the Native case.

  $ ../standalone.exe -impl input.re.ml | ocamlformat - --enable-outside-detected-project --impl
  doNativeLogic ();;
  
  let value = doNativeLogic ()
  let universal_fn () = doNativeLogic ()
  let universal_fn_with_arg1 arg1 = doNativeLogic arg1
