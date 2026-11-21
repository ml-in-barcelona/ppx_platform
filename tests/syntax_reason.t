Reason syntax: each input is a .re file that refmt prints as OCaml before the
ppx runs, as a Reason project build does. Each case shows the Native output and
compiles it on Native and on Melange (-js). The inputs have no interface file,
so warning 70 (missing mli) is off everywhere.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ cat > js.ml << 'EOF'
  > let log _ = ()
  > EOF
  $ cat > react.ml << 'EOF'
  > let useState init = (init (), fun (_ : 'a -> 'a) -> ())
  > let useEffect0 (f : unit -> (unit -> unit) option) = ignore f
  > EOF
  $ ocamlc -c ppx_platform.ml js.ml react.ml

1. let%melange_only (top-level, rec, rec and, local, local rec, unit),
[%melange_only (y) => ...], switch%platform, and [@melange_only] /
[@native_only] on items

  $ cat > bindings.re << 'EOF'
  > let%melange_only topLevel = x => Js.log(x);
  > 
  > let%melange_only rec countdown = n =>
  >   if (n > 0) {
  >     countdown(n - 1);
  >   } else {
  >     Js.log(n);
  >   };
  > 
  > let%melange_only rec isEven = n => n == 0 || isOdd(n - 1)
  > and isOdd = n => n != 0 && isEven(n - 1);
  > 
  > let localBinding = x => {
  >   let%melange_only handler = () => Js.log(x);
  >   ignore(handler);
  > };
  > 
  > let localRec = x => {
  >   let%melange_only rec loop = n =>
  >     if (n > 0) {
  >       loop(n - 1);
  >     } else {
  >       Js.log(x);
  >     };
  >   ignore(loop);
  > };
  > 
  > let localUnit = x => {
  >   let%melange_only () = Js.log(x);
  >   ();
  > };
  > 
  > let extensionFun = x => {
  >   let h = [%melange_only (y) => Js.log((x, y))];
  >   ignore(h);
  > };
  > 
  > let switchPlatform = (x, y) =>
  >   switch%platform () {
  >   | Native => y
  >   | Melange => x + 1
  >   };
  > 
  > [@melange_only]
  > let droppedItem = Js.log(1);
  > 
  > [@native_only]
  > let keptItem = 1;
  > EOF

  $ refmt --print ml bindings.re > bindings.ml
  $ ./standalone.exe -impl bindings.ml | ocamlformat - --enable-outside-detected-project --impl > bindings_native.ml
  $ ./standalone.exe -impl bindings.ml -js | ocamlformat - --enable-outside-detected-project --impl > bindings_js.ml
  $ cat bindings_native.ml
  let (topLevel
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "topLevel")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let rec (countdown
           [@alert
             melange_only
               "This value only exists in the Melange build. Use it inside a \
                let%melange_only function, or a Melange branch of \
                match%platform."]) =
   (fun n ->
    let _ = countdown in
    let _ = n in
    Ppx_platform.fail_melange_only "countdown")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let rec (isEven
           [@alert
             melange_only
               "This value only exists in the Melange build. Use it inside a \
                let%melange_only function, or a Melange branch of \
                match%platform."]) =
   (fun n ->
    let _ = isOdd in
    let _ = n in
    Ppx_platform.fail_melange_only "isEven")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  and (isOdd
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun n ->
    let _ = isEven in
    let _ = n in
    Ppx_platform.fail_melange_only "isOdd")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let localBinding x =
    let handler _ =
      let _ = x in
      Ppx_platform.fail_melange_only "handler"
        [@@alert "-melange_only"]
    in
    ignore handler
  
  let localRec x =
    let rec loop n =
      let _ = loop in
      let _ = n in
      let _ = x in
      Ppx_platform.fail_melange_only "loop"
        [@@alert "-melange_only"]
    in
    ignore loop
  
  let localUnit x =
    let () =
      let _ = x in
      ()
    in
    ()
  
  let extensionFun x =
    let h y =
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "y"
    in
    ignore h
  
  let switchPlatform x =
   fun y ->
    let _ = x in
    y
  
  let keptItem = 1
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only bindings_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only bindings_js.ml

The Melange build keeps the other branch, so there y gets the ignore:

  $ grep -A 3 "let switchPlatform" bindings_js.ml
  let switchPlatform x =
   fun y ->
    let _ = y in
    x + 1

2. Labelled ~x, optional ~y=?, default ~z=1, unit, tuple and record
destructuring, in the discarded function and in the enclosing function

  $ cat > params.re << 'EOF'
  > let%melange_only labelled = (~x, ~y=?, ~z=1, (), (a, b), {contents}) =>
  >   Js.log((x, y, z, a, b, contents));
  > 
  > let enclosing = (~x, ~y=?, ~z=1, (a, b), {contents}, ()) => {
  >   let%melange_only handler = () => Js.log((x, y, z, a, b, contents));
  >   ignore(handler);
  > };
  > 
  > let enclosingSwitch = (~x, ~y=?, ~z=1, (a, b), ()) =>
  >   switch%platform () {
  >   | Native => ()
  >   | Melange => Js.log((x, y, z, a, b))
  >   };
  > 
  > let destructured = ((a, b)) => [%melange_only () => Js.log(a + b)];
  > 
  > let curried = x => [%melange_only (a, b) => Js.log((x, a, b))];
  > EOF

  $ refmt --print ml params.re > params.ml
  $ ./standalone.exe -impl params.ml | ocamlformat - --enable-outside-detected-project --impl > params_native.ml
  $ ./standalone.exe -impl params.ml -js | ocamlformat - --enable-outside-detected-project --impl > params_js.ml
  $ cat params_native.ml
  let (labelled
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ~x ?y ?(z = 1) _ _ _ ->
    let _ = x in
    let _ = y in
    let _ = z in
    Ppx_platform.fail_melange_only "labelled")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let enclosing ~x =
   fun ?y ->
    fun ?(z = 1) ->
     fun (a, b) ->
      fun { contents } ->
       fun () ->
        let handler _ =
          let _ = a in
          let _ = b in
          let _ = contents in
          let _ = x in
          let _ = y in
          let _ = z in
          Ppx_platform.fail_melange_only "handler"
            [@@alert "-melange_only"]
        in
        ignore handler
  
  let enclosingSwitch ~x =
   fun ?y ->
    fun ?(z = 1) ->
     fun (a, b) ->
      fun () ->
       let _ = a in
       let _ = b in
       let _ = x in
       let _ = y in
       let _ = z in
       ()
  
  let destructured (a, b) =
   fun _ ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "<unknown>"
  
  let curried x =
   fun a b ->
    let _ = a in
    let _ = b in
    let _ = x in
    Ppx_platform.fail_melange_only "a"
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only params_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only params_js.ml

3. React-style hooks without JSX: the state setter is used only in discarded
code

  $ cat > hooks.re << 'EOF'
  > let useEffectSetter = () => {
  >   let (count, setCount) = React.useState(() => 0);
  >   React.useEffect0(
  >     [%melange_only
  >       () => {
  >         setCount(n => n + 1);
  >         None;
  >       }
  >     ],
  >   );
  >   count;
  > };
  > 
  > let useSwitchSetter = () => {
  >   let (count, setCount) = React.useState(() => 0);
  >   let onClick =
  >     switch%platform () {
  >     | Native => (_ => ())
  >     | Melange => (_ => setCount(n => n + 1))
  >     };
  >   (count, onClick);
  > };
  > 
  > let useLocalHandler = () => {
  >   let (count, setCount) = React.useState(() => 0);
  >   let%melange_only onClick = _ => setCount(n => n + 1);
  >   ignore(onClick);
  >   count;
  > };
  > EOF

  $ refmt --print ml hooks.re > hooks.ml
  $ ./standalone.exe -impl hooks.ml | ocamlformat - --enable-outside-detected-project --impl > hooks_native.ml
  $ ./standalone.exe -impl hooks.ml -js | ocamlformat - --enable-outside-detected-project --impl > hooks_js.ml
  $ cat hooks_native.ml
  let useEffectSetter () =
    let count, setCount = React.useState (fun () -> 0) in
    React.useEffect0 (fun _ ->
        let _ = setCount in
        Ppx_platform.fail_melange_only "<unknown>");
    count
  
  let useSwitchSetter () =
    let count, setCount = React.useState (fun () -> 0) in
    let onClick =
      let _ = setCount in
      fun _ -> ()
    in
    (count, onClick)
  
  let useLocalHandler () =
    let count, setCount = React.useState (fun () -> 0) in
    let onClick _ =
      let _ = setCount in
      Ppx_platform.fail_melange_only "onClick"
        [@@alert "-melange_only"]
    in
    ignore onClick;
    count
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only hooks_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only hooks_js.ml

4. Local opens M.(...) and { open M; ... }, and top-level values. Only the
local x gets an ignore; y from the open, topValue and M.y do not. On Native
the open is used only in discarded code, so warning 33 (unused open) is off
there: that is the accepted cost recorded in in_scope_idents_unsupported.t.

  $ cat > opens.re << 'EOF'
  > module M = {
  >   let y = 2;
  > };
  > 
  > let topValue = 1;
  > 
  > let localOpenParen = x => M.([%melange_only () => Js.log((x, y))]);
  > 
  > let localOpenBlock = x => {
  >   open M;
  >   let%melange_only handler = () => Js.log((x, y, topValue));
  >   ignore(handler);
  > };
  > 
  > let topLevelNotIgnored = () =>
  >   switch%platform () {
  >   | Native => 0
  >   | Melange => topValue + M.y
  >   };
  > EOF

  $ refmt --print ml opens.re > opens.ml
  $ ./standalone.exe -impl opens.ml | ocamlformat - --enable-outside-detected-project --impl > opens_native.ml
  $ ./standalone.exe -impl opens.ml -js | ocamlformat - --enable-outside-detected-project --impl > opens_js.ml
  $ cat opens_native.ml
  module M = struct
    let y = 2
  end
  
  let topValue = 1
  
  let localOpenParen x =
    let open M in
    fun _ ->
      let _ = x in
      Ppx_platform.fail_melange_only "<unknown>"
  
  let localOpenBlock x =
    let open M in
    let handler _ =
      let _ = x in
      Ppx_platform.fail_melange_only "handler"
        [@@alert "-melange_only"]
    in
    ignore handler
  
  let topLevelNotIgnored () = 0
  $ ocamlc -c -w +A-33-70 -warn-error +A -alert @melange_only opens_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only opens_js.ml

5. A local name that discarded code shadows before use gets no ignore. Here x
is unused on both platforms, so both builds report warning 27; warnings are
not errors in this section.

  $ cat > shadow.re << 'EOF'
  > let shadowedByLet = x => {
  >   let%melange_only handler = () => {
  >     let x = 1;
  >     Js.log(x);
  >   };
  >   ignore(handler);
  > };
  > 
  > let shadowedByParam = x => {
  >   let h = [%melange_only x => Js.log(x)];
  >   ignore(h);
  > };
  > 
  > let shadowedInSwitch = x =>
  >   switch%platform () {
  >   | Native => ()
  >   | Melange =>
  >     let x = 2;
  >     Js.log(x);
  >   };
  > EOF

  $ refmt --print ml shadow.re > shadow.ml
  $ ./standalone.exe -impl shadow.ml | ocamlformat - --enable-outside-detected-project --impl > shadow_native.ml
  $ ./standalone.exe -impl shadow.ml -js | ocamlformat - --enable-outside-detected-project --impl > shadow_js.ml
  $ cat shadow_native.ml
  let shadowedByLet x =
    let handler _ =
      Ppx_platform.fail_melange_only "handler"
        [@@alert "-melange_only"]
    in
    ignore handler
  
  let shadowedByParam x =
    let h x =
      let _ = x in
      Ppx_platform.fail_melange_only "x"
    in
    ignore h
  
  let shadowedInSwitch x = ()
  $ ocamlc -c -w +A-70 -alert @melange_only shadow_native.ml
  File "shadow_native.ml", line 1, characters 18-19:
  1 | let shadowedByLet x =
                        ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_native.ml", line 8, characters 20-21:
  8 | let shadowedByParam x =
                          ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_native.ml", line 15, characters 21-22:
  15 | let shadowedInSwitch x = ()
                            ^
  Warning 27 [unused-var-strict]: unused variable x.
  $ ocamlc -c -w +A-70 -alert -melange_only shadow_js.ml
  File "shadow_js.ml", line 1, characters 18-19:
  1 | let shadowedByLet x =
                        ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_js.ml", line 8, characters 20-21:
  8 | let shadowedByParam x =
                          ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_js.ml", line 12, characters 21-22:
  12 | let shadowedInSwitch x =
                            ^
  Warning 27 [unused-var-strict]: unused variable x.

6. On expressions and local bindings, the attribute that drops code on the
current platform is an error, as in platform.t

  $ cat > errors.re << 'EOF'
  > let melangeOnlyExpr = x => [@melange_only] Js.log(x);
  > 
  > let nativeOnlyExpr = x => [@native_only] (x + 1);
  > 
  > let melangeOnlyLocal = x => {
  >   [@melange_only]
  >   let y = x;
  >   y;
  > };
  > EOF

  $ refmt --print ml errors.re > errors.ml
  $ ./standalone.exe -impl errors.ml | ocamlformat - --enable-outside-detected-project --impl
  let melangeOnlyExpr x =
    [%ocaml.error
      "Don't use melange_only on expressions, use switch%platform instead"]
  
  let nativeOnlyExpr x = x + 1
  
  let melangeOnlyLocal x =
    [%ocaml.error
      "Don't use melange_only on expressions, use switch%platform instead"]
  $ ./standalone.exe -impl errors.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let melangeOnlyExpr x = Js.log x
  
  let nativeOnlyExpr x =
    [%ocaml.error
      "Don't use native_only on expressions, use switch%platform instead"]
  
  let melangeOnlyLocal x =
    let y = x in
    y

The ppx removes the platform attributes from the items and expressions it
keeps (see keptItem in section 1 and nativeOnlyExpr above):

  $ grep -n "keptItem\|droppedItem" bindings_native.ml bindings_js.ml
  bindings_native.ml:88:let keptItem = 1
  bindings_js.ml:28:let droppedItem = Js.log 1

Known issues

[@melange_only] on a local open M.(...) drops only the open on Native and keeps
the body, so names from the open are unbound. Expected: the same error as for
other expressions in section 6. The ppx gets the same tree for
`let open [@melange_only] M in e`, where dropping only the open is the
documented behaviour (at_melange_only.t), so it cannot tell the two forms
apart.

  $ cat > open_attr.re << 'EOF'
  > module M = {
  >   let y = 2;
  > };
  > 
  > let openAttr = x => [@melange_only] M.(x + y);
  > EOF

  $ refmt --print ml open_attr.re > open_attr.ml
  $ ./standalone.exe -impl open_attr.ml | ocamlformat - --enable-outside-detected-project --impl > open_attr_native.ml
  $ cat open_attr_native.ml
  module M = struct
    let y = 2
  end
  
  let openAttr x = x + y
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only open_attr_native.ml
  File "open_attr_native.ml", line 5, characters 21-22:
  5 | let openAttr x = x + y
                           ^
  Error: Unbound value y
  [2]
