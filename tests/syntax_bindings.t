Binding forms and patterns around and inside discarded code.

A plain name bound locally in the enclosing expression and used only in
discarded code gets a `let _ = name` at the kept position. A name that the
discarded code shadows before it uses it gets none, and still warns. A name
used in both the kept and the discarded code gets none.

The inputs have no .mli, so every top-level value is exported. The compile
commands add -70 to -w +A only to silence the missing-interface warning.

A local let%melange_only stub has the melange_only alert, so a native use of
it fails under -alert @melange_only (section 7). The inputs that use a local
stub outside a Melange branch mark the use with
[@alert "-melange_only"].

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. Binding forms around discarded code: let, sequential lets, let rec,
let ... and ..., let rec ... and ..., let open, let open!, M.(e),
open struct ... end, let module, let exception, binding operators, local
let%melange_only (plain, and, rec, rec ... and ...), [%melange_only fun ...]
and a top-level let%melange_only rec ... and ...

  $ cat > lets_input.ml << 'EOF'
  > module M = struct
  >   let k = 1
  > end
  > 
  > exception Top of int
  > 
  > let ( let* ) o f = Option.bind o f
  > let ( and* ) a b = match (a, b) with Some a, Some b -> Some (a, b) | _ -> None
  > let ( let+ ) o f = Option.map f o
  > 
  > let let_plain () =
  >   let only_mel = 1 in
  >   let both = 2 in
  >   match%platform () with Native -> both | Melange -> both + only_mel
  > 
  > let let_sequential () =
  >   let a = 1 in
  >   let b = a + 1 in
  >   let c = 3 in
  >   match%platform () with Native -> a | Melange -> b + c
  > 
  > let let_rec n =
  >   let rec loop i = if i > 0 then loop (i - 1) else 0 in
  >   match%platform () with Native -> n | Melange -> loop n
  > 
  > let let_and () =
  >   let a = 1 and b = 2 in
  >   match%platform () with Native -> a | Melange -> a + b
  > 
  > let let_rec_and n =
  >   let rec even i = i = 0 || odd (i - 1) and odd i = i <> 0 && even (i - 1) in
  >   match%platform () with Native -> even n | Melange -> odd n
  > 
  > let let_open x =
  >   let open M in
  >   match%platform () with Native -> k | Melange -> k + x
  > 
  > let let_open_bang x =
  >   let open! M in
  >   match%platform () with Native -> k | Melange -> k + x
  > 
  > let local_open x = M.(match%platform () with Native -> k | Melange -> k + x)
  > 
  > let open_struct x =
  >   let open struct
  >     let hidden = 2
  >   end in
  >   match%platform () with Native -> hidden | Melange -> hidden + x
  > 
  > let let_module x =
  >   let module L = struct
  >     let v = 1
  >   end in
  >   match%platform () with Native -> L.v | Melange -> L.v + x
  > 
  > let let_exception x =
  >   let exception Stop of int in
  >   match%platform () with
  >   | Native -> ( try raise (Stop 0) with Stop n -> n)
  >   | Melange -> ( try raise (Stop x) with Stop n -> n)
  > 
  > let letop o1 o2 =
  >   let* a = o1 and* b = o2 in
  >   let+ c = Some 1 in
  >   match%platform () with Native -> a + c | Melange -> a + b + c
  > 
  > let mel_only_local x y =
  >   let%melange_only f () = x + y in
  >   match%platform () with Native -> y | Melange -> f ()
  > 
  > let mel_only_and x y =
  >   let%melange_only f () = x and g () = y in
  >   match%platform () with Native -> 0 | Melange -> f () + g ()
  > 
  > let mel_only_rec n =
  >   let%melange_only rec down i = if i > 0 then down (i - 1) else n in
  >   match%platform () with Native -> 0 | Melange -> down n
  > 
  > let mel_only_fun x y =
  >   let h = [%melange_only fun () -> x + y] in
  >   ignore h;
  >   y
  > 
  > let mel_only_rec_and n =
  >   let%melange_only rec even i = i = 0 || odd (i - 1)
  >   and odd i = i <> 0 && even (i - 1) in
  >   match%platform () with Native -> false | Melange -> even n
  > 
  > let%melange_only rec top_even i = i = 0 || top_odd (i - 1)
  > and top_odd i = i <> 0 && top_even (i - 1)
  > EOF

  $ ./standalone.exe -impl lets_input.ml | ocamlformat - --enable-outside-detected-project --impl > lets_native.ml
  $ ./standalone.exe -impl lets_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > lets_js.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only -I . lets_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only -I . lets_js.ml
  $ cat lets_native.ml
  module M = struct
    let k = 1
  end
  
  exception Top of int
  
  let ( let* ) o f = Option.bind o f
  let ( and* ) a b = match (a, b) with Some a, Some b -> Some (a, b) | _ -> None
  let ( let+ ) o f = Option.map f o
  
  let let_plain () =
    let only_mel = 1 in
    let both = 2 in
    let _ = only_mel in
    both
  
  let let_sequential () =
    let a = 1 in
    let b = a + 1 in
    let c = 3 in
    let _ = b in
    let _ = c in
    a
  
  let let_rec n =
    let rec loop i = if i > 0 then loop (i - 1) else 0 in
    let _ = loop in
    n
  
  let let_and () =
    let a = 1 and b = 2 in
    let _ = b in
    a
  
  let let_rec_and n =
    let rec even i = i = 0 || odd (i - 1) and odd i = i <> 0 && even (i - 1) in
    let _ = odd in
    even n
  
  let let_open x =
    let open M in
    let _ = x in
    k
  
  let let_open_bang x =
    let open! M in
    let _ = x in
    k
  
  let local_open x =
    let open M in
    let _ = x in
    k
  
  let open_struct x =
    let open struct
      let hidden = 2
    end in
    let _ = x in
    hidden
  
  let let_module x =
    let module L = struct
      let v = 1
    end in
    let _ = x in
    L.v
  
  let let_exception x =
    let exception Stop of int in
    let _ = x in
    try raise (Stop 0) with Stop n -> n
  
  let letop o1 o2 =
    let* a = o1 and* b = o2 in
    let+ c = Some 1 in
    let _ = b in
    a + c
  
  let mel_only_local x y =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ ->
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
       [@@alert "-melange_only"]
    in
    let _ = (f [@alert "-melange_only"]) in
    y
  
  let mel_only_and x y =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ ->
      let _ = x in
      Ppx_platform.fail_melange_only "f"
    [@@alert "-melange_only"]
    and (g
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ ->
      let _ = y in
      Ppx_platform.fail_melange_only "g"
       [@@alert "-melange_only"]
    in
    let _ = (f [@alert "-melange_only"]) in
    let _ = (g [@alert "-melange_only"]) in
    0
  
  let mel_only_rec n =
    let rec (down
             [@alert
               melange_only
                 "This value only exists in the Melange build. Use it inside a \
                  let%melange_only function, or a Melange branch of \
                  match%platform."]) =
     fun i ->
      let _ = down in
      let _ = i in
      let _ = n in
      Ppx_platform.fail_melange_only "down"
       [@@alert "-melange_only"]
    in
    let _ = (down [@alert "-melange_only"]) in
    let _ = n in
    0
  
  let mel_only_fun x y =
    let h _ =
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "lets_input.ml:80:11"
    in
    ignore h;
    y
  
  let mel_only_rec_and n =
    let rec (even
             [@alert
               melange_only
                 "This value only exists in the Melange build. Use it inside a \
                  let%melange_only function, or a Melange branch of \
                  match%platform."]) =
     fun i ->
      let _ = i in
      let _ = odd in
      Ppx_platform.fail_melange_only "even"
    [@@alert "-melange_only"]
    and (odd
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun i ->
      let _ = even in
      let _ = i in
      Ppx_platform.fail_melange_only "odd"
       [@@alert "-melange_only"]
    in
    let _ = (even [@alert "-melange_only"]) in
    let _ = n in
    false
  
  let rec (top_even
           [@alert
             melange_only
               "This value only exists in the Melange build. Use it inside a \
                let%melange_only function, or a Melange branch of \
                match%platform."]) =
   (fun i ->
    let _ = i in
    let _ = top_odd in
    Ppx_platform.fail_melange_only "top_even")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  and (top_odd
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun i ->
    let _ = i in
    let _ = top_even in
    Ppx_platform.fail_melange_only "top_odd")
    [@alert "-melange_only"]
  [@@warning "-32"]

On js, only the names used only in the Native branch get an ignore:

  $ grep -n "let _" lets_js.ml
  20:  let _ = a in
  33:  let _ = even in
  71:  let _ = y in

2. Pattern forms that bind names: var, alias, tuple, record with punning and
`; _`, constructor with arguments, polymorphic variant, array, list cons,
or-pattern, lazy, constraint, exception pattern, `_`-prefixed names, and
patterns of a local let. In each case one name is used in both branches and
one only in the Melange branch. A `_`-prefixed name also gets an ignore; this
is harmless.

  $ cat > patterns_input.ml << 'EOF'
  > type r = { a : int; b : int; c : int }
  > type c = C of int * int | D of int
  > type ab = A of int * int | B of int * int
  > 
  > exception E of int * int
  > 
  > let p_var mel both =
  >   match%platform () with Native -> both | Melange -> both + mel
  > 
  > let p_alias ((first, _) as pair) =
  >   match%platform () with Native -> first | Melange -> first + fst pair
  > 
  > let p_tuple (t1, t2) =
  >   match%platform () with Native -> t1 | Melange -> t1 + t2
  > 
  > let p_record { a; b = rb; _ } =
  >   match%platform () with Native -> a | Melange -> a + rb
  > 
  > let p_construct = function
  >   | C (c1, c2) -> (
  >       match%platform () with Native -> c1 | Melange -> c1 + c2)
  >   | D _ -> 0
  > 
  > let p_variant = function
  >   | `P (v1, v2) -> (
  >       match%platform () with Native -> v1 | Melange -> v1 + v2)
  >   | `Q -> 0
  > 
  > let p_array = function
  >   | [| e1; e2 |] -> (
  >       match%platform () with Native -> e1 | Melange -> e1 + e2)
  >   | _ -> 0
  > 
  > let p_cons = function
  >   | hd :: tl -> (
  >       match%platform () with
  >       | Native -> hd
  >       | Melange -> hd + List.length tl)
  >   | [] -> 0
  > 
  > let p_or (A (o1, o2) | B (o2, o1)) =
  >   match%platform () with Native -> o1 | Melange -> o1 + o2
  > 
  > let p_lazy (lazy lz) (lazy lboth) =
  >   match%platform () with Native -> lboth | Melange -> lboth + lz
  > 
  > let p_constraint (ct : int) (cboth : int) =
  >   match%platform () with Native -> cboth | Melange -> cboth + ct
  > 
  > let p_exception f =
  >   match f () with
  >   | v -> v
  >   | exception E (x1, x2) -> (
  >       match%platform () with Native -> x1 | Melange -> x1 + x2)
  > 
  > let p_underscore _u _ub =
  >   match%platform () with Native -> _ub | Melange -> _ub + _u
  > 
  > let p_let_tuple p =
  >   let ((l1, l2) as lp) = p in
  >   match%platform () with Native -> l1 | Melange -> l1 + l2 + fst lp
  > 
  > let p_mel_only_fun { a; b; _ } =
  >   let h = [%melange_only fun () -> a + b] in
  >   ignore h;
  >   a
  > 
  > let p_mel_only_let (lazy lz) (q1, q2) =
  >   let%melange_only f () = lz + q1 + q2 in
  >   ignore f [@alert "-melange_only"];
  >   q1
  > EOF

  $ ./standalone.exe -impl patterns_input.ml | ocamlformat - --enable-outside-detected-project --impl > patterns_native.ml
  $ ./standalone.exe -impl patterns_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > patterns_js.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only -I . patterns_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only -I . patterns_js.ml
  $ cat patterns_native.ml
  type r = { a : int; b : int; c : int }
  type c = C of int * int | D of int
  type ab = A of int * int | B of int * int
  
  exception E of int * int
  
  let p_var mel both =
    let _ = mel in
    both
  
  let p_alias ((first, _) as pair) =
    let _ = pair in
    first
  
  let p_tuple (t1, t2) =
    let _ = t2 in
    t1
  
  let p_record { a; b = rb; _ } =
    let _ = rb in
    a
  
  let p_construct = function
    | C (c1, c2) ->
        let _ = c2 in
        c1
    | D _ -> 0
  
  let p_variant = function
    | `P (v1, v2) ->
        let _ = v2 in
        v1
    | `Q -> 0
  
  let p_array = function
    | [| e1; e2 |] ->
        let _ = e2 in
        e1
    | _ -> 0
  
  let p_cons = function
    | hd :: tl ->
        let _ = tl in
        hd
    | [] -> 0
  
  let p_or (A (o1, o2) | B (o2, o1)) =
    let _ = o2 in
    o1
  
  let p_lazy (lazy lz) (lazy lboth) =
    let _ = lz in
    lboth
  
  let p_constraint (ct : int) (cboth : int) =
    let _ = ct in
    cboth
  
  let p_exception f =
    match f () with
    | v -> v
    | exception E (x1, x2) ->
        let _ = x2 in
        x1
  
  let p_underscore _u _ub =
    let _ = _u in
    _ub
  
  let p_let_tuple p =
    let ((l1, l2) as lp) = p in
    let _ = l2 in
    let _ = lp in
    l1
  
  let p_mel_only_fun { a; b; _ } =
    let h _ =
      let _ = a in
      let _ = b in
      Ppx_platform.fail_melange_only "patterns_input.ml:64:11"
    in
    ignore h;
    a
  
  let p_mel_only_let (lazy lz) (q1, q2) =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ ->
      let _ = lz in
      let _ = q1 in
      let _ = q2 in
      Ppx_platform.fail_melange_only "f"
       [@@alert "-melange_only"]
    in
    ignore f [@alert "-melange_only"];
    q1

3. The discarded code binds a name but still reads the outer one: the RHS of
let ... and ..., one branch that shadows and one that does not, a punned
record expression, a guard, a default parameter, the RHS of a value in
open struct, a member of a local module next to the outer name, a for-loop
bound, the RHS of a binding operator, and a local open in a pattern. Each
outer name gets an ignore.

  $ cat > outer_input.ml << 'EOF'
  > module P = struct
  >   type t = W of int
  > end
  > 
  > type r = { x : int }
  > 
  > let ( let* ) o f = Option.bind o f
  > 
  > let and_rhs x =
  >   match%platform () with Native -> 0 | Melange -> let x = 1 and y = x in x + y
  > 
  > let one_branch_shadows x =
  >   match%platform () with Native -> 0 | Melange -> (let x = 1 in x) + x
  > 
  > let punned_record x =
  >   match%platform () with Native -> 0 | Melange -> { x }.x
  > 
  > let guard_uses x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match 1 with y when y > x -> y | _ -> 0)
  > 
  > let default_param x =
  >   match%platform () with Native -> 0 | Melange -> (fun ?(y = x) () -> y) ()
  > 
  > let open_struct_rhs x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let open struct
  >         let x = x + 1
  >       end in
  >       x
  > 
  > let let_module_member x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let module L = struct
  >         let x = 2
  >       end in
  >       L.x + x
  > 
  > let for_bound x =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> for i = x to 1 do ignore i done
  > 
  > let letop_rhs x =
  >   match%platform () with Native -> None | Melange -> let* x = Some x in Some x
  > 
  > let pat_open x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match P.W 1 with P.(W y) -> y + x)
  > 
  > let pat_open_shadow (P.(W w)) x =
  >   match%platform () with Native -> x | Melange -> w
  > EOF

  $ ./standalone.exe -impl outer_input.ml | ocamlformat - --enable-outside-detected-project --impl > outer_native.ml
  $ ./standalone.exe -impl outer_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > outer_js.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only -I . outer_native.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only -I . outer_js.ml
  $ cat outer_native.ml
  module P = struct
    type t = W of int
  end
  
  type r = { x : int }
  
  let ( let* ) o f = Option.bind o f
  
  let and_rhs x =
    let _ = x in
    0
  
  let one_branch_shadows x =
    let _ = x in
    0
  
  let punned_record x =
    let _ = x in
    0
  
  let guard_uses x =
    let _ = x in
    0
  
  let default_param x =
    let _ = x in
    0
  
  let open_struct_rhs x =
    let _ = x in
    0
  
  let let_module_member x =
    let _ = x in
    0
  
  let for_bound x =
    let _ = x in
    ()
  
  let letop_rhs x =
    let _ = x in
    None
  
  let pat_open x =
    let _ = x in
    0
  
  let pat_open_shadow P.(W w) x =
    let _ = w in
    x

4. The discarded code shadows the outer `x` with each binding form and each
pattern form before it reads it. No ignore is emitted, so the unused `x` still
warns 27 on native, and also on js, where the Melange code reads only the
inner `x`. The `_x` case does not warn.

  $ cat > shadow_input.ml << 'EOF'
  > type r = { x : int }
  > type c = C of int * int
  > type ab = A of int | B of int
  > 
  > exception E of int
  > 
  > let ( let* ) o f = Option.bind o f
  > 
  > let s_let x =
  >   match%platform () with Native -> 0 | Melange -> let x = 1 in x
  > 
  > let s_let_rec x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> let rec x n = if n > 0 then x (n - 1) else n in x 2
  > 
  > let s_let_and x =
  >   match%platform () with Native -> 0 | Melange -> let x = 1 and y = 2 in x + y
  > 
  > let s_sequential x =
  >   match%platform () with Native -> 0 | Melange -> let y = 1 in let x = y in x
  > 
  > let s_open_struct x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let open struct
  >         let x = 3
  >       end in
  >       x
  > 
  > let s_letop x =
  >   match%platform () with
  >   | Native -> None
  >   | Melange -> let* x = Some 1 in Some x
  > 
  > let s_fun x =
  >   match%platform () with Native -> 0 | Melange -> (fun x -> x) 1
  > 
  > let s_alias x =
  >   match%platform () with Native -> 0 | Melange -> let (_, _) as x = (1, 2) in fst x
  > 
  > let s_tuple x =
  >   match%platform () with Native -> 0 | Melange -> let x, _ = (1, 2) in x
  > 
  > let s_record x =
  >   match%platform () with Native -> 0 | Melange -> let { x } = { x = 1 } in x
  > 
  > let s_construct x =
  >   match%platform () with Native -> 0 | Melange -> let (C (x, _)) = C (1, 2) in x
  > 
  > let s_variant x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match `P 1 with `P x -> x | `Q -> 0)
  > 
  > let s_array x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match [| 1 |] with [| x |] -> x | _ -> 0)
  > 
  > let s_cons x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match [ 1 ] with x :: _ -> x | [] -> 0)
  > 
  > let s_or x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match A 1 with A x | B x -> x)
  > 
  > let s_lazy x =
  >   match%platform () with Native -> 0 | Melange -> let (lazy x) = lazy 1 in x
  > 
  > let s_constraint x =
  >   match%platform () with Native -> 0 | Melange -> let (x : int) = 1 in x
  > 
  > let s_exception x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match raise (E 1) with () -> 0 | exception E x -> x)
  > 
  > let s_guard x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> ( match 1 with x when x > 0 -> x | _ -> 0)
  > 
  > let s_for x =
  >   match%platform () with
  >   | Native -> ()
  >   | Melange -> for x = 0 to 1 do ignore x done
  > 
  > let s_underscore _x =
  >   match%platform () with Native -> 0 | Melange -> let _x = 1 in _x
  > 
  > let s_mel_only_fun x =
  >   let h = [%melange_only fun () -> let x = 1 in x] in
  >   ignore h
  > 
  > let s_mel_only_let x =
  >   let%melange_only f () = match Some 1 with Some x -> x | None -> 0 in
  >   ignore f [@alert "-melange_only"]
  > EOF

  $ ./standalone.exe -impl shadow_input.ml | ocamlformat - --enable-outside-detected-project --impl > shadow_native.ml
  $ ./standalone.exe -impl shadow_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > shadow_js.ml
  $ grep -c "let _" shadow_native.ml
  0
  [1]
  $ ocamlc -c -w +A-70 -alert @melange_only -I . shadow_native.ml 2>&1 | grep -E 'Warning|^ *[0-9]+ \| '
  8 | let s_let x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  9 | let s_let_rec x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  10 | let s_let_and x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  11 | let s_sequential x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  12 | let s_open_struct x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  13 | let s_letop x = None
  Warning 27 [unused-var-strict]: unused variable x.
  14 | let s_fun x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  15 | let s_alias x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  16 | let s_tuple x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  17 | let s_record x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  18 | let s_construct x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  19 | let s_variant x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  20 | let s_array x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  21 | let s_cons x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  22 | let s_or x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  23 | let s_lazy x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  24 | let s_constraint x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  25 | let s_exception x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  26 | let s_guard x = 0
  Warning 27 [unused-var-strict]: unused variable x.
  27 | let s_for x = ()
  Warning 27 [unused-var-strict]: unused variable x.
  30 | let s_mel_only_fun x =
  Warning 27 [unused-var-strict]: unused variable x.
  34 | let s_mel_only_let x =
  Warning 27 [unused-var-strict]: unused variable x.
  $ ocamlc -c -w +A-70 -alert -melange_only -I . shadow_js.ml 2>&1 | grep Warning | sort | uniq -c
       22 Warning 27 [unused-var-strict]: unused variable x.

5. A first-class module unpack `(module U : S)` binds a module, which never
gets an ignore. The plain `x` next to it, used only in the Melange branch,
does. On native, `U` used only in the Melange branch warns 60, an accepted
cost.

  $ cat > modules_input.ml << 'EOF'
  > module type S = sig
  >   val v : int
  > end
  > 
  > let unpack (module U : S) x =
  >   match%platform () with Native -> 0 | Melange -> U.v + x
  > 
  > let unpack_both (module U : S) x =
  >   match%platform () with Native -> U.v | Melange -> U.v + x
  > EOF

  $ ./standalone.exe -impl modules_input.ml | ocamlformat - --enable-outside-detected-project --impl > modules_native.ml
  $ ./standalone.exe -impl modules_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > modules_js.ml
  $ grep -n "let _" modules_native.ml modules_js.ml
  modules_native.ml:6:  let _ = x in
  modules_native.ml:10:  let _ = x in
  $ ocamlc -c -w +A-70 -alert @melange_only -I . modules_native.ml
  File "modules_native.ml", line 5, characters 19-20:
  5 | let unpack (module U : S) x =
                         ^
  Warning 60 [unused-module]: unused module U.
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only -I . modules_js.ml

6. The initializer of an object `val x = x` reads the outer `x`, so that `x`,
used only in the Melange branch, gets an ignore. A name that an
`open struct ... end` binds is not a local: the Melange branch of
open_struct_shadows_local reads the `x` of the struct, so no ignore names it.
The outer `x` is unused on both targets and warns 27; on native the `x` of the
struct is unused too and warns 32.

  $ cat > val_open_input.ml << 'EOF'
  > let object_val x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       (object
  >          val x = x
  >          method get = x
  >       end)#get
  > 
  > let open_struct_shadows_local x =
  >   let open struct
  >     let x = 2
  >   end in
  >   match%platform () with Native -> 0 | Melange -> x
  > EOF

  $ ./standalone.exe -impl val_open_input.ml | ocamlformat - --enable-outside-detected-project --impl > val_open_native.ml
  $ ./standalone.exe -impl val_open_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > val_open_js.ml
  $ cat val_open_native.ml
  let object_val x =
    let _ = x in
    0
  
  let open_struct_shadows_local x =
    let open struct
      let x = 2
    end in
    0
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only -I . val_open_native.ml
  File "val_open_native.ml", line 5, characters 30-31:
  5 | let open_struct_shadows_local x =
                                    ^
  Error (warning 27 [unused-var-strict]): unused variable x.
  
  File "val_open_native.ml", line 7, characters 8-9:
  7 |     let x = 2
              ^
  Error (warning 32 [unused-value-declaration]): unused value x.
  [2]
  $ ocamlc -c -w +A-70 -alert -melange_only -I . val_open_js.ml
  File "val_open_js.ml", line 8, characters 30-31:
  8 | let open_struct_shadows_local x =
                                    ^
  Warning 27 [unused-var-strict]: unused variable x.

7. A let%melange_only stub carries the melange_only alert on the names it
binds, so native code that uses it fails under -alert @melange_only. This
holds for a local stub, and for a top-level binding whose pattern has a type
constraint or an alias: the alert goes on each name in the pattern, after the
attributes the pattern already has. The ignores that the ppx adds, and uses in
the Melange branch of match%platform, do not trigger the alert. Only a name
bound to a local stub in scope gets the alert suppression: the parameter `f`
of `k` has the name of the stub in `h`, and its ignore has no attribute.

  $ cat > alert_input.ml << 'EOF'
  > let%melange_only (typed : int -> unit) = fun x -> print_int x
  > let%melange_only ((aliased as alias) : int -> unit) = fun x -> print_int x
  > let%melange_only ((attributed [@user]) : int -> unit) = fun x -> print_int x
  > 
  > let top_use () =
  >   typed 1;
  >   aliased 2;
  >   alias 3;
  >   attributed 4
  > 
  > let local_use x =
  >   let%melange_only f y = print_int (x + y) in
  >   f 1
  > 
  > let local_in_melange_branch x =
  >   let%melange_only f y = print_int (x + y) in
  >   match%platform () with Native -> () | Melange -> f 1
  > 
  > let h () =
  >   let%melange_only f () = 1 in
  >   match%platform () with Native -> 0 | Melange -> f ()
  > 
  > let k (f : unit -> int) =
  >   match%platform () with Native -> () | Melange -> ignore (f ())
  > EOF

  $ ./standalone.exe -impl alert_input.ml | ocamlformat - --enable-outside-detected-project --impl > alert_native.ml
  $ ./standalone.exe -impl alert_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > alert_js.ml
  $ cat alert_native.ml
  let (typed
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) :
      int -> unit =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "typed")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let (((aliased
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        as alias)
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) :
      int -> unit =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "alert_input.ml:2:18")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let (attributed
       [@user]
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) :
      int -> unit =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "attributed")
    [@alert "-melange_only"]
  [@@warning "-32"]
  
  let top_use () =
    typed 1;
    aliased 2;
    alias 3;
    attributed 4
  
  let local_use x =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun y ->
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
       [@@alert "-melange_only"]
    in
    f 1
  
  let local_in_melange_branch x =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun y ->
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
       [@@alert "-melange_only"]
    in
    let _ = (f [@alert "-melange_only"]) in
    ()
  
  let h () =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =
     fun _ -> Ppx_platform.fail_melange_only "f"
       [@@alert "-melange_only"]
    in
    let _ = (f [@alert "-melange_only"]) in
    0
  
  let k (f : unit -> int) =
    let _ = f in
    ()
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only alert_native.ml
  File "alert_native.ml", line 44, characters 2-7:
  44 |   typed 1;
         ^^^^^
  Error (alert melange_only): typed
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  
  File "alert_native.ml", line 45, characters 2-9:
  45 |   aliased 2;
         ^^^^^^^
  Error (alert melange_only): aliased
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  
  File "alert_native.ml", line 46, characters 2-7:
  46 |   alias 3;
         ^^^^^
  Error (alert melange_only): alias
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  
  File "alert_native.ml", line 47, characters 2-12:
  47 |   attributed 4
         ^^^^^^^^^^
  Error (alert melange_only): attributed
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  
  File "alert_native.ml", line 62, characters 2-3:
  62 |   f 1
         ^
  Error (alert melange_only): f
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  [2]
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only alert_js.ml
