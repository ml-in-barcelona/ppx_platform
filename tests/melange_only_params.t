  $ cat > input.ml << EOF
  > let%melange_only two_args a b = a + b
  > 
  > let%melange_only optional_args ?abort ?(base = 1) () =
  >   ignore abort;
  >   base
  > 
  > let%melange_only labelled_args ~first ~(second : int) = first + second
  > 
  > let%melange_only constrained : int -> int -> int = fun a b -> a + b
  > 
  > let%melange_only newtype (type a) (x : a) (y : a) = [ x; y ]
  > 
  > let%melange_only cases a = function 0 -> a | n -> n + a
  > 
  > let make () =
  >   let%melange_only inner a b = a + b in
  >   inner
  > 
  > let expression = [%melange_only fun a b -> a + b]
  > 
  > module type S = sig
  >   val x : int
  > end
  > 
  > let%melange_only fcm1 (module M : S) a = M.x + a
  > 
  > let%melange_only fcm2 a (module M : S) = M.x + a
  > 
  > module type Js_only = sig
  >   val x : int
  > end
  > [@@melange_only]
  > 
  > let%melange_only fcm3 (module M : Js_only) = M.x
  > EOF

  $ cat > input.mli << EOF
  > val two_args : int -> int -> int
  > val optional_args : ?abort:bool -> ?base:int -> unit -> int
  > val labelled_args : first:int -> second:int -> int
  > val constrained : int -> int -> int
  > val newtype : 'a -> 'a -> 'a list
  > val cases : int -> int -> int
  > val make : unit -> int -> int -> int
  > val expression : int -> int -> int
  > 
  > module type S = sig
  >   val x : int
  > end
  > 
  > val fcm1 : (module S) -> int -> int
  > val fcm2 : int -> (module S) -> int
  > EOF

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl > native.ml
  $ cat native.ml
  let (two_args
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun a b -> Ppx_platform.fail_melange_only "two_args") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (optional_args
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ?abort ?base () ->
    Ppx_platform.fail_melange_only "optional_args")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (labelled_args
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ~first ~second ->
    Ppx_platform.fail_melange_only "labelled_args")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (constrained
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun a b ->
    Ppx_platform.fail_melange_only "constrained")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (newtype
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun (type a) x y ->
    Ppx_platform.fail_melange_only "newtype")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (cases
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun a _ -> Ppx_platform.fail_melange_only "cases") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let make () =
    let inner a b =
      Ppx_platform.fail_melange_only "inner"
        [@@alert "-melange_only"]
    in
    inner
  
  let expression a b = Ppx_platform.fail_melange_only "a"
  
  module type S = sig
    val x : int
  end
  
  let (fcm1
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun _ a -> Ppx_platform.fail_melange_only "fcm1") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (fcm2
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun a _ -> Ppx_platform.fail_melange_only "fcm2") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (fcm3
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun _ -> Ppx_platform.fail_melange_only "fcm3") [@alert "-melange_only"]
  [@@warning "-27-32"]

The native output keeps every parameter in its inferred type

  $ cat $INSIDE_DUNE/src/runtime/ppx_platform.ml > ppx_platform.ml
  $ ocamlc -c ppx_platform.ml
  $ ocamlc -i -alert -melange_only native.ml
  val two_args : 'a -> 'b -> 'c
  val optional_args : ?abort:'a -> ?base:'b -> unit -> 'c
  val labelled_args : first:'a -> second:'b -> 'c
  val constrained : 'a -> 'b -> 'c
  val newtype : 'a -> 'b -> 'c
  val cases : 'a -> 'b -> 'c
  val make : unit -> 'a -> 'b -> 'c
  val expression : 'a -> 'b -> 'c
  module type S = sig val x : int end
  val fcm1 : 'a -> 'b -> 'c
  val fcm2 : 'a -> 'b -> 'c
  val fcm3 : 'a -> 'b

The native output type-checks against the full signature

  $ cp input.mli native.mli
  $ ocamlc -c native.mli
  $ ocamlc -c -alert -melange_only native.ml

Partial application does not raise; full application raises Melange_only

  $ cat > main.ml << EOF
  > let raises name f =
  >   match f () with
  >   | _ -> print_endline (name ^ ": no raise")
  >   | exception Ppx_platform.Melange_only n -> print_endline (name ^ ": raises " ^ n)
  > 
  > let () =
  >   raises "two_args partial" (fun () -> ignore (Native.two_args 1));
  >   raises "two_args full" (fun () -> Native.two_args 1 2);
  >   raises "optional_args partial" (fun () -> ignore (Native.optional_args ~abort:true));
  >   raises "optional_args full" (fun () -> Native.optional_args ());
  >   raises "labelled_args partial" (fun () -> ignore (Native.labelled_args ~first:1));
  >   raises "constrained partial" (fun () -> ignore (Native.constrained 1));
  >   raises "newtype partial" (fun () -> ignore (Native.newtype 1));
  >   raises "newtype full" (fun () -> Native.newtype 1 2);
  >   raises "cases partial" (fun () -> ignore (Native.cases 1));
  >   raises "cases full" (fun () -> Native.cases 1 2);
  >   raises "inner partial" (fun () -> ignore (Native.make () 1));
  >   raises "expression partial" (fun () -> ignore (Native.expression 1));
  >   raises "expression full" (fun () -> Native.expression 1 2)
  > EOF
  $ ocamlc -w -5 -alert -melange_only ppx_platform.cmo native.cmo main.ml -o main.exe
  $ OCAMLRUNPARAM=b=0 ./main.exe
  two_args partial: no raise
  two_args full: raises two_args
  optional_args partial: no raise
  optional_args full: raises optional_args
  labelled_args partial: no raise
  constrained partial: no raise
  newtype partial: no raise
  newtype full: raises newtype
  cases partial: no raise
  cases full: raises cases
  inner partial: no raise
  expression partial: no raise
  expression full: raises a

The -js output type-checks against the same signature

  $ ./standalone.exe -impl input.ml -js > melange.ml
  $ cp input.mli melange.mli
  $ ocamlc -c melange.mli
  $ ocamlc -c melange.ml
