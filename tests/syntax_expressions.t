Expression and control-flow forms around discarded code.

Discarded code is the Melange branch of match%platform, the body of
[%melange_only fun ...] and the body of let%melange_only on native, and the
Native branch of match%platform with -js. Each case shows the native output,
then compiles it on native and in js mode. The inputs have no interface file,
so every case disables warning 70 (missing-mli); every top-level value is
exported.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. Control flow: match with guards and `when`, match with exception, try/with,
if/then/else (each arm and the condition), while (body and condition), for
to/downto with an index that only discarded code uses, sequences, assert and
lazy. A name that kept code also uses outside the match%platform, such as `n`
in while_loop or `v` and `limit` in match_guard, still gets an ignore; it is
redundant but harmless.

  $ cat > control.ml << 'EOF'
  > let match_guard opt limit =
  >   match opt with
  >   | Some v when v > limit ->
  >       let h = [%melange_only fun () -> print_int (v + limit)] in
  >       ignore h
  >   | Some v -> ignore v
  >   | None -> ()
  > 
  > let match_guard_discarded opt limit =
  >   match opt with
  >   | Some v when (match%platform () with Native -> true | Melange -> v > limit) -> ()
  >   | _ -> ()
  > 
  > let match_exception f =
  >   match f () with
  >   | v -> (match%platform () with Native -> () | Melange -> print_int v)
  >   | exception Failure msg ->
  >       (match%platform () with Native -> () | Melange -> print_string msg)
  > 
  > let try_with f =
  >   try f ()
  >   with Failure msg ->
  >     let%melange_only report () = print_string msg in
  >     ignore report
  > 
  > let if_branches cond a b =
  >   if cond then (match%platform () with Native -> () | Melange -> print_int a)
  >   else (match%platform () with Native -> () | Melange -> print_int b)
  > 
  > let if_condition flag =
  >   if (match%platform () with Native -> true | Melange -> flag) then 1 else 0
  > 
  > let while_loop count =
  >   let n = ref 0 in
  >   while !n < count do
  >     (match%platform () with Native -> () | Melange -> print_int !n);
  >     incr n
  >   done
  > 
  > let while_condition stop =
  >   while (match%platform () with Native -> false | Melange -> stop ()) do
  >     ()
  >   done
  > 
  > let for_up () =
  >   for i = 0 to 2 do
  >     match%platform () with Native -> () | Melange -> print_int i
  >   done
  > 
  > let for_down () =
  >   for j = 2 downto 0 do
  >     let h = [%melange_only fun () -> print_int j] in
  >     ignore h
  >   done
  > 
  > let sequence a =
  >   print_newline ();
  >   (match%platform () with Native -> () | Melange -> print_int a);
  >   print_newline ()
  > 
  > let assert_discarded x =
  >   assert (match%platform () with Native -> true | Melange -> x > 0)
  > 
  > let lazy_discarded x =
  >   lazy (match%platform () with Native -> 0 | Melange -> x)
  > EOF

  $ ./standalone.exe -impl control.ml | ocamlformat - --enable-outside-detected-project --impl > control_native.ml
  $ ./standalone.exe -impl control.ml -js | ocamlformat - --enable-outside-detected-project --impl > control_js.ml
  $ cat control_native.ml
  let match_guard opt limit =
    match opt with
    | Some v when v > limit ->
        let h _ =
          let _ = limit in
          let _ = v in
          Ppx_platform.fail_melange_only "<unknown>"
        in
        ignore h
    | Some v -> ignore v
    | None -> ()
  
  let match_guard_discarded opt limit =
    match opt with
    | Some v
      when let _ = limit in
           let _ = v in
           true ->
        ()
    | _ -> ()
  
  let match_exception f =
    match f () with
    | v ->
        let _ = v in
        ()
    | exception Failure msg ->
        let _ = msg in
        ()
  
  let try_with f =
    try f ()
    with Failure msg ->
      let report _ =
        let _ = msg in
        Ppx_platform.fail_melange_only "report"
          [@@alert "-melange_only"]
      in
      ignore report
  
  let if_branches cond a b =
    if cond then
      let _ = a in
      ()
    else
      let _ = b in
      ()
  
  let if_condition flag =
    if
      let _ = flag in
      true
    then 1
    else 0
  
  let while_loop count =
    let n = ref 0 in
    while !n < count do
      (let _ = n in
       ());
      incr n
    done
  
  let while_condition stop =
    while
      let _ = stop in
      false
    do
      ()
    done
  
  let for_up () =
    for i = 0 to 2 do
      let _ = i in
      ()
    done
  
  let for_down () =
    for j = 2 downto 0 do
      let h _ =
        let _ = j in
        Ppx_platform.fail_melange_only "<unknown>"
      in
      ignore h
    done
  
  let sequence a =
    print_newline ();
    (let _ = a in
     ());
    print_newline ()
  
  let assert_discarded x =
    assert (
      let _ = x in
      true)
  
  let lazy_discarded x =
    lazy
      (let _ = x in
       0)
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only control_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only control_js.ml

2. Data and application forms: record creation with punning, `{ r with ... }`,
field access, field assignment, record patterns, array and list literals,
tuples, polymorphic variants, constructors with inline records, string and
format literals, a local custom infix operator, pipes `|>` and `@@`, labelled
and optional arguments, first-class module unpack and pack. A local operator
is a plain name, so it gets an ignore too. Field and constructor names are not
values and get none.

  $ cat > data.ml << 'EOF'
  > type r = { name : string; mutable count : int }
  > module type V = sig
  >   val v : int
  > end
  > 
  > type shape = Circle of int | Square of { side : int }
  > 
  > let record_create name count =
  >   match%platform () with
  >   | Native -> { name = "native"; count = 0 }
  >   | Melange -> { name; count }
  > 
  > let record_with base extra =
  >   match%platform () with
  >   | Native -> base
  >   | Melange -> { base with count = base.count + extra }
  > 
  > let record_field r =
  >   let%melange_only get () = r.name in
  >   ignore get
  > 
  > let record_setfield r value =
  >   match%platform () with Native -> () | Melange -> r.count <- value
  > 
  > let record_pattern { name; count } =
  >   match%platform () with Native -> () | Melange -> print_string name; print_int count
  > 
  > let collections a b =
  >   match%platform () with
  >   | Native -> ([||], [], ())
  >   | Melange -> ([| a; b |], [ a; b ], ())
  > 
  > let tuple a b =
  >   match%platform () with Native -> (0, 0) | Melange -> (a, b)
  > 
  > let poly_variant x =
  >   match%platform () with Native -> `None | Melange -> `Some x
  > 
  > let constructors side radius =
  >   match%platform () with
  >   | Native -> [ Circle 0 ]
  >   | Melange -> [ Circle radius; Square { side } ]
  > 
  > let strings name =
  >   match%platform () with
  >   | Native -> ""
  >   | Melange -> Printf.sprintf "%s %d" name (String.length {|raw|})
  > 
  > let operators a b =
  >   let ( +++ ) x y = x + y + 1 in
  >   match%platform () with Native -> 0 | Melange -> (a + b) * a +++ b
  > 
  > let pipes x f g =
  >   match%platform () with Native -> () | Melange -> x |> f |> g @@ ()
  > 
  > let labelled ~label ?opt value =
  >   let use ~label ?opt v = ignore (label, opt, v) in
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> use ~label ?opt value
  > 
  > let first_class_module (type a) (m : (module Set.S with type elt = a)) x =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange ->
  >       let (module S) = m in
  >       ignore (S.singleton x)
  > 
  > let pack_module x =
  >   match%platform () with
  >   | Native -> None
  >   | Melange ->
  >       Some (module struct let v = x end : V)
  > EOF

  $ ./standalone.exe -impl data.ml | ocamlformat - --enable-outside-detected-project --impl > data_native.ml
  $ ./standalone.exe -impl data.ml -js | ocamlformat - --enable-outside-detected-project --impl > data_js.ml
  $ cat data_native.ml
  type r = { name : string; mutable count : int }
  
  module type V = sig
    val v : int
  end
  
  type shape = Circle of int | Square of { side : int }
  
  let record_create name count =
    let _ = count in
    let _ = name in
    { name = "native"; count = 0 }
  
  let record_with base extra =
    let _ = extra in
    base
  
  let record_field r =
    let get _ =
      let _ = r in
      Ppx_platform.fail_melange_only "get"
        [@@alert "-melange_only"]
    in
    ignore get
  
  let record_setfield r value =
    let _ = r in
    let _ = value in
    ()
  
  let record_pattern { name; count } =
    let _ = count in
    let _ = name in
    ()
  
  let collections a b =
    let _ = a in
    let _ = b in
    ([||], [], ())
  
  let tuple a b =
    let _ = a in
    let _ = b in
    (0, 0)
  
  let poly_variant x =
    let _ = x in
    `None
  
  let constructors side radius =
    let _ = radius in
    let _ = side in
    [ Circle 0 ]
  
  let strings name =
    let _ = name in
    ""
  
  let operators a b =
    let ( +++ ) x y = x + y + 1 in
    let _ = ( +++ ) in
    let _ = a in
    let _ = b in
    0
  
  let pipes x f g =
    let _ = f in
    let _ = g in
    let _ = x in
    ()
  
  let labelled ~label ?opt value =
    let use ~label ?opt v = ignore (label, opt, v) in
    let _ = label in
    let _ = opt in
    let _ = use in
    let _ = value in
    ()
  
  let first_class_module (type a) (m : (module Set.S with type elt = a)) x =
    let _ = m in
    let _ = x in
    ()
  
  let pack_module x =
    let _ = x in
    None
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only data_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only data_js.ml

3. Objects and classes: object self and instance variables (also mutable,
assigned with `<-`), a method that is a [%melange_only fun ...], a class with a
`let` before `object`, a class written with `fun`, and an object inside
discarded code. In a class, a method that is [%melange_only fun ...] keeps its
type through a method type annotation; see the known issues for the form
without one. In a class, `self` and instance variables used only in
discarded code get an ignore, as in an immediate object.

  $ cat > objects.ml << 'EOF'
  > let immediate_object x =
  >   object (self)
  >     val state = x
  >     val mutable hits = 0
  >     method get = state
  >     method touch =
  >       match%platform () with
  >       | Native -> ()
  >       | Melange -> hits <- hits + 1; ignore (self#get + state)
  >   end
  > 
  > let object_method_fun () =
  >   object (self)
  >     val label = "o"
  >     method name = label
  >     method handler = [%melange_only fun () -> print_string (self#name ^ label)]
  >   end
  > 
  > class counter (init : int) =
  >   let step = 2 in
  >   object
  >     val mutable value = init
  >     method value = value
  >     method bump =
  >       match%platform () with
  >       | Native -> ()
  >       | Melange -> value <- value + step
  >   end
  > 
  > class with_fun =
  >   fun (prefix : string) ->
  >   object
  >     method show : string -> unit =
  >       [%melange_only fun suffix -> print_string (prefix ^ suffix)]
  >   end
  > 
  > let object_in_discarded x =
  >   match%platform () with
  >   | Native -> None
  >   | Melange -> Some (object method v = x end)
  > EOF

  $ ./standalone.exe -impl objects.ml | ocamlformat - --enable-outside-detected-project --impl > objects_native.ml
  $ ./standalone.exe -impl objects.ml -js | ocamlformat - --enable-outside-detected-project --impl > objects_js.ml
  $ cat objects_native.ml
  let immediate_object x =
    object (self)
      val state = x
      val mutable hits = 0
      method get = state
  
      method touch =
        let _ = hits in
        let _ = self in
        let _ = state in
        ()
    end
  
  let object_method_fun () =
    object (self)
      val label = "o"
      method name = label
  
      method handler _ =
        let _ = label in
        let _ = self in
        Ppx_platform.fail_melange_only "<unknown>"
    end
  
  class counter (init : int) =
    let step = 2 in
    object
      val mutable value = init
      method value = value
  
      method bump =
        let _ = step in
        let _ = value in
        ()
    end
  
  class with_fun (prefix : string) =
    object
      method show : string -> unit =
        fun suffix ->
          let _ = prefix in
          let _ = suffix in
          Ppx_platform.fail_melange_only "suffix"
    end
  
  let object_in_discarded x =
    let _ = x in
    None
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only objects_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only objects_js.ml

4. match%platform forms: both branch orders, a branch with locals the other
branch does not have, match%platform nested in either branch with the inner
cases in the other order, let%melange_only inside a branch, attributes inside
discarded code, an attribute on match%platform itself, and [@native_only] on an
expression in the Native branch. The js output keeps the opposite branches.

  $ cat > platform.ml << 'EOF'
  > let melange_first a b =
  >   match%platform () with Melange -> a + 1 | Native -> b + 1
  > 
  > let native_first a b =
  >   match%platform () with Native -> a + 1 | Melange -> b + 1
  > 
  > let branch_locals x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let local = x * 2 in
  >       local + x
  > 
  > let nested_native_in_melange a b c =
  >   match%platform () with
  >   | Native -> a
  >   | Melange -> (
  >       match%platform () with Melange -> b | Native -> c)
  > 
  > let nested_in_native a b c =
  >   match%platform () with
  >   | Melange -> a
  >   | Native -> (
  >       match%platform () with Native -> b | Melange -> c)
  > 
  > let nested_melange_only_in_branch x =
  >   match%platform () with
  >   | Native -> ignore
  >   | Melange ->
  >       let%melange_only inner () = print_int x in
  >       inner
  > 
  > let attributes_inside x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let[@inline] double y = y * 2 in
  >       (double x [@ocaml.warning "-26"])
  > 
  > let attribute_on_platform x =
  >   (match%platform () with Native -> 0 | Melange -> x) [@ocaml.warning "-27"]
  > 
  > let native_only_expr x =
  >   match%platform () with
  >   | Native -> (x + 1 [@native_only])
  >   | Melange -> x
  > EOF

  $ ./standalone.exe -impl platform.ml | ocamlformat - --enable-outside-detected-project --impl > platform_native.ml
  $ ./standalone.exe -impl platform.ml -js | ocamlformat - --enable-outside-detected-project --impl > platform_js.ml
  $ cat platform_native.ml
  let melange_first a b =
    let _ = a in
    b + 1
  
  let native_first a b =
    let _ = b in
    a + 1
  
  let branch_locals x =
    let _ = x in
    0
  
  let nested_native_in_melange a b c =
    let _ = b in
    let _ = c in
    a
  
  let nested_in_native a b c =
    let _ = a in
    let _ = c in
    b
  
  let nested_melange_only_in_branch x =
    let _ = x in
    ignore
  
  let attributes_inside x =
    let _ = x in
    0
  
  let attribute_on_platform x =
    (let _ = x in
     0)
    [@ocaml.warning "-27"]
  
  let native_only_expr x = x + 1
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only platform_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only platform_js.ml

  $ cat platform_js.ml
  let melange_first a b =
    let _ = b in
    a + 1
  
  let native_first a b =
    let _ = a in
    b + 1
  
  let branch_locals x =
    let local = x * 2 in
    local + x
  
  let nested_native_in_melange a b c =
    let _ = a in
    let _ = c in
    b
  
  let nested_in_native a b c =
    let _ = b in
    let _ = c in
    a
  
  let nested_melange_only_in_branch x =
    let inner () = print_int x in
    inner
  
  let attributes_inside x =
    let double y = y * 2 [@@inline] in
    (double x [@ocaml.warning "-26"])
  
  let attribute_on_platform x = x [@ocaml.warning "-27"]
  let native_only_expr x = x

5. Other extension nodes inside discarded code are dropped on native with the
rest of the code, as is [@melange_only] on an expression in the Melange branch.
With -js the extension nodes stay in the output, and the [@melange_only]
attribute goes away from the code it keeps. No ppx in this test expands `[%foo]` or
`[%bar.baz]`, so the js output is not compiled; the grep shows the nodes are
kept unchanged.

  $ cat > extensions.ml << 'EOF'
  > let other_extension x =
  >   match%platform () with Native -> 0 | Melange -> [%foo x]
  > 
  > let other_extension_in_fun x =
  >   let%melange_only f () = [%bar.baz x] in
  >   ignore f
  > 
  > let melange_only_attr_in_melange_branch x =
  >   match%platform () with Native -> 0 | Melange -> (x + 1 [@melange_only])
  > EOF

  $ ./standalone.exe -impl extensions.ml | ocamlformat - --enable-outside-detected-project --impl > extensions_native.ml
  $ ./standalone.exe -impl extensions.ml -js | ocamlformat - --enable-outside-detected-project --impl > extensions_js.ml
  $ cat extensions_native.ml
  let other_extension x =
    let _ = x in
    0
  
  let other_extension_in_fun x =
    let f _ =
      let _ = x in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let melange_only_attr_in_melange_branch x =
    let _ = x in
    0
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only extensions_native.ml
  $ grep -n "%foo\|%bar\|melange_only" extensions_js.ml
  1:let other_extension x = [%foo x]
  4:  let f () = [%bar.baz x] in
  7:let melange_only_attr_in_melange_branch x = x + 1

6. On kept code, [@melange_only] on an expression on native, [@native_only] on
an expression with -js, and [%melange_only] on a value that is not a function
are errors. The attribute that keeps an expression goes away from it.

  $ cat > expr_attrs.ml << 'EOF'
  > let melange_attr x = print_int (x + 1 [@melange_only])
  > let native_attr x = print_int (x + 1 [@native_only])
  > let melange_only_value x = [%melange_only x + 1]
  > EOF

  $ ./standalone.exe -impl expr_attrs.ml | ocamlformat - --enable-outside-detected-project --impl
  let melange_attr x =
    print_int
      [%ocaml.error
        "Don't use melange_only on expressions, use switch%platform instead"]
  
  let native_attr x = print_int (x + 1)
  
  let melange_only_value x =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  $ ./standalone.exe -impl expr_attrs.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let melange_attr x = print_int (x + 1)
  
  let native_attr x =
    print_int
      [%ocaml.error
        "Don't use native_only on expressions, use switch%platform instead"]
  
  let melange_only_value x = x + 1

7. A local that discarded code shadows with a match case, a for index, a try
handler, an object instance variable or a function parameter is not used. It
gets no ignore and still warns on both targets. These compiles do not turn
warnings into errors, so that all warnings show.

  $ cat > shadow.ml << 'EOF'
  > let match_shadow x y =
  >   match%platform () with
  >   | Native -> ignore y
  >   | Melange -> ( match y with x -> ignore x)
  > 
  > let for_shadow i =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> for i = 0 to 1 do print_int i done
  > 
  > let try_shadow e =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> ( try () with e -> raise e)
  > 
  > let object_shadow v =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> ignore (object val v = 1 method get = v end)
  > 
  > let fun_shadow f =
  >   match%platform () with Native -> () | Melange -> ignore (fun f -> f)
  > EOF

  $ ./standalone.exe -impl shadow.ml | ocamlformat - --enable-outside-detected-project --impl > shadow_native.ml
  $ ./standalone.exe -impl shadow.ml -js | ocamlformat - --enable-outside-detected-project --impl > shadow_js.ml
  $ cat shadow_native.ml
  let match_shadow x y = ignore y
  let for_shadow i = ()
  let try_shadow e = ()
  let object_shadow v = ()
  let fun_shadow f = ()
  $ ocamlc -c -w +A-70 -alert @melange_only shadow_native.ml
  File "shadow_native.ml", line 1, characters 17-18:
  1 | let match_shadow x y = ignore y
                       ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_native.ml", line 2, characters 15-16:
  2 | let for_shadow i = ()
                     ^
  Warning 27 [unused-var-strict]: unused variable i.
  
  File "shadow_native.ml", line 3, characters 15-16:
  3 | let try_shadow e = ()
                     ^
  Warning 27 [unused-var-strict]: unused variable e.
  
  File "shadow_native.ml", line 4, characters 18-19:
  4 | let object_shadow v = ()
                        ^
  Warning 27 [unused-var-strict]: unused variable v.
  
  File "shadow_native.ml", line 5, characters 15-16:
  5 | let fun_shadow f = ()
                     ^
  Warning 27 [unused-var-strict]: unused variable f.
  $ ocamlc -c -w +A-70 -alert -melange_only shadow_js.ml
  File "shadow_js.ml", line 1, characters 17-18:
  1 | let match_shadow x y = match y with x -> ignore x
                       ^
  Warning 27 [unused-var-strict]: unused variable x.
  
  File "shadow_js.ml", line 3, characters 15-16:
  3 | let for_shadow i =
                     ^
  Warning 27 [unused-var-strict]: unused variable i.
  
  File "shadow_js.ml", line 8, characters 15-16:
  8 | let try_shadow e = try () with e -> raise e
                     ^
  Warning 27 [unused-var-strict]: unused variable e.
  
  File "shadow_js.ml", line 10, characters 18-19:
  10 | let object_shadow v =
                         ^
  Warning 27 [unused-var-strict]: unused variable v.
  
  File "shadow_js.ml", line 17, characters 15-16:
  17 | let fun_shadow f = ignore (fun f -> f)
                      ^
  Warning 27 [unused-var-strict]: unused variable f.

8. A local exception that only discarded code uses gets no ignore, so native
warns 38 (unused-extension). A local module warns 60 in the same way (see
in_scope_idents.t). Both are accepted costs: an exception or a module is not a
value, so `let _ = name` cannot name it.

  $ cat > local_exception.ml << 'EOF'
  > let local_exception x =
  >   let exception Local of int in
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> ( try raise (Local x) with Local y -> print_int y)
  > EOF

  $ ./standalone.exe -impl local_exception.ml | ocamlformat - --enable-outside-detected-project --impl > local_exception_native.ml
  $ ./standalone.exe -impl local_exception.ml -js | ocamlformat - --enable-outside-detected-project --impl > local_exception_js.ml
  $ cat local_exception_native.ml
  let local_exception x =
    let exception Local of int in
    let _ = x in
    ()
  $ ocamlc -c -w +A-70 -alert @melange_only local_exception_native.ml
  File "local_exception_native.ml", line 2, characters 16-28:
  2 |   let exception Local of int in
                      ^^^^^^^^^^^^
  Warning 38 [unused-extension]: unused exception Local
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only local_exception_js.ml

9. In a class (not an immediate object), `self` that only discarded code uses
gets an ignore, so native compiles.

  $ cat > class_self.ml << 'EOF'
  > class class_self =
  >   object (self)
  >     method get = 1
  >     method run = match%platform () with Native -> () | Melange -> ignore self#get
  >   end
  > EOF

  $ ./standalone.exe -impl class_self.ml | ocamlformat - --enable-outside-detected-project --impl > class_self_native.ml
  $ ./standalone.exe -impl class_self.ml -js | ocamlformat - --enable-outside-detected-project --impl > class_self_js.ml
  $ cat class_self_native.ml
  class class_self =
    object (self)
      method get = 1
  
      method run =
        let _ = self in
        ()
    end
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only class_self_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only class_self_js.ml

Known issues

A. In a class, a method that is [%melange_only fun x -> ...] without a method
type annotation loses the parameter type on native, and the class fails with
an unbound type variable. A type constraint inside the extension does not help:
the stub drops it, because it can name types that exist only in the Melange
build. The method type annotation in section 3 compiles.

  $ cat > class_method_fun.ml << 'EOF'
  > class class_untyped_method_fun =
  >   object
  >     method show = [%melange_only fun suffix -> print_string suffix]
  >   end
  > EOF

  $ ./standalone.exe -impl class_method_fun.ml | ocamlformat - --enable-outside-detected-project --impl > class_method_fun_native.ml
  $ ./standalone.exe -impl class_method_fun.ml -js | ocamlformat - --enable-outside-detected-project --impl > class_method_fun_js.ml
  $ cat class_method_fun_native.ml
  class class_untyped_method_fun =
    object
      method show suffix =
        let _ = suffix in
        Ppx_platform.fail_melange_only "suffix"
    end
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only class_method_fun_native.ml
  File "class_method_fun_native.ml", lines 1-6, characters 0-5:
  1 | class class_untyped_method_fun =
  2 |   object
  3 |     method show suffix =
  4 |       let _ = suffix in
  5 |       Ppx_platform.fail_melange_only "suffix"
  6 |   end
  Error: Some type variables are unbound in this type:
           class class_untyped_method_fun : object method show : 'a -> 'b end
         The method show has type 'a -> 'b where 'a is unbound
  [2]
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only class_method_fun_js.ml

B. [@melange_only] on a pattern makes the pattern `_` on Native. In a parameter
this drops a Melange-only name (see at_melange_only.t), but in a match case the
case then matches every value, so `B` gives 1 on Native:

  $ printf 'let pat = function `A [@melange_only] -> 1 | `B -> 2\n' > pattern_attr.ml
  $ ./standalone.exe -impl pattern_attr.ml | ocamlformat - --enable-outside-detected-project --impl
  let pat = function _ -> 1 | `B -> 2
