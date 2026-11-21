Nested

  $ cat > input.ml << EOF
  >  module X = struct
  >    include struct
  >    type t = Js.Json.t
  >    let a = 2 + 2
  >    end [@@melange_only]
  >  
  >    include struct
  >      type t = Js.Json.t
  >      let a = 4 + 4
  >    end [@@native_only]
  >  end
  > EOF

With -js flag it picks the block with `[@@melange_only]`

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  module X = struct
    include struct
      type t = Js.Json.t
  
      let a = 2 + 2
    end
  end

Without -js flag, it picks the block with `[@@native_only]`

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  module X = struct
    include struct
      type t = Js.Json.t
  
      let a = 4 + 4
    end
  end

Pstr_include

  $ cat > input.ml << EOF
  > include struct
  >   type t = Js.Json.t
  > end [@@melange_only]
  > 
  > include struct
  >   type t = string
  > end [@@native_only]
  > EOF

With -js flag it picks the block with `[@@melange_only]`

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Js.Json.t
  end

Without -js flag, it picks the block with `[@@native_only]`

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = string
  end

Use only one of the platforms

  $ cat > input.ml << EOF
  > include struct
  >   type t = Js.Json.t
  > end [@@melange_only]
  > 
  > include struct
  >   type t = string
  > end
  > EOF

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = string
  end

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Js.Json.t
  end
  
  include struct
    type t = string
  end

Pstr_module

  $ cat > input_module.ml << EOF
  > module M = struct
  >   let x = 42
  > end [@@melange_only]
  > module M = struct
  >   let x = 44
  > end [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_module.ml | ocamlformat - --enable-outside-detected-project --impl
  module M = struct
    let x = 44
  end

  $ ./standalone.exe -impl input_module.ml -js | ocamlformat - --enable-outside-detected-project --impl
  module M = struct
    let x = 42
  end

Pstr_value

  $ cat > input_let.ml << EOF
  > let x = 42 [@@melange_only]
  > let y = 44 [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_let.ml | ocamlformat - --enable-outside-detected-project --impl
  let y = 44

  $ ./standalone.exe -impl input_let.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let x = 42

Pstr_open

  $ cat > input_open.ml << EOF
  > open Printf [@@melange_only]
  > open List [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_open.ml | ocamlformat - --enable-outside-detected-project --impl
  open List

  $ ./standalone.exe -impl input_open.ml -js | ocamlformat - --enable-outside-detected-project --impl
  open Printf

Pstr_exception

  $ cat > input_exception.ml << EOF
  > exception MyException of string [@@melange_only]
  > exception AnotherException of int [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_exception.ml | ocamlformat - --enable-outside-detected-project --impl
  exception AnotherException of int

  $ ./standalone.exe -impl input_exception.ml -js | ocamlformat - --enable-outside-detected-project --impl
  exception MyException of string

Pstr_primitive

  $ cat > input_primitive.ml << EOF
  > external add : int -> int -> int = "caml_add_int" [@@melange_only]
  > external subtract : int -> int -> int = "caml_subtract_int" [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_primitive.ml | ocamlformat - --enable-outside-detected-project --impl
  external subtract : int -> int -> int = "caml_subtract_int"

  $ ./standalone.exe -impl input_primitive.ml -js | ocamlformat - --enable-outside-detected-project --impl
  external add : int -> int -> int = "caml_add_int"

Pstr_eval (doesn't work)

  $ cat > input_primitive.ml << EOF
  > include struct
  >   2 [@@melange_only]
  > end
  > 
  > include struct
  >   3 [@@native_only]
  > end
  > EOF

  $ ./standalone.exe -impl input_primitive.ml | ocamlformat - --enable-outside-detected-project --impl
  include struct end
  
  include struct
    3
  end

  $ ./standalone.exe -impl input_primitive.ml -js | ocamlformat - --enable-outside-detected-project --impl
  include struct
    2
  end
  
  include struct end

Pstr_type

  $ cat > input_type.ml << EOF
  > type point = { x : int; y : int } [@@melange_only]
  > type color = Red | Green | Blue [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_type.ml | ocamlformat - --enable-outside-detected-project --impl
  type color = Red | Green | Blue

  $ ./standalone.exe -impl input_type.ml -js | ocamlformat - --enable-outside-detected-project --impl
  type point = { x : int; y : int }

Pstr_recmodule

  $ cat > input_recmodule.ml << EOF
  > module rec M = struct
  >   let x = 42
  > end [@@melange_only]
  > module rec M = struct
  >   let x = 44
  > end [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_recmodule.ml | ocamlformat - --enable-outside-detected-project --impl
  module rec M = struct
    let x = 44
  end

  $ ./standalone.exe -impl input_recmodule.ml -js | ocamlformat - --enable-outside-detected-project --impl
  module rec M = struct
    let x = 42
  end

Pstr_class

  $ cat > input_class.ml << EOF
  > class virtual ['a] base x = object
  >   method get = x
  > end [@@melange_only]
  > class derived = object
  >   inherit base 42
  > end [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_class.ml | ocamlformat - --enable-outside-detected-project --impl
  class derived =
    object
      inherit base 42
    end

  $ ./standalone.exe -impl input_class.ml -js | ocamlformat - --enable-outside-detected-project --impl
  class virtual ['a] base x =
    object
      method get = x
    end

Pstr_class_type

  $ cat > input_class_type.ml << EOF
  > class type base = object
  >   method get : int
  > end [@@melange_only]
  > class type derived = object
  >   inherit base
  > end [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_class_type.ml | ocamlformat - --enable-outside-detected-project --impl
  class type derived = object
    inherit base
  end

  $ ./standalone.exe -impl input_class_type.ml -js | ocamlformat - --enable-outside-detected-project --impl
  class type base = object
    method get : int
  end

Pexp_open with a platform attribute is an error in the build that drops it,
located at the open, that says where to move the open:

  $ cat > input_pexp_open.ml << EOF
  > let f () =
  >   let open [@native_only] Unix in
  >   let open [@melange_only] Webapi.Dom in
  >   42
  > EOF

  $ ./standalone.exe -impl input_pexp_open.ml | ocamlformat - --enable-outside-detected-project --impl
  let f () =
    let open Unix in
    [%ocaml.error
      "Don't use melange_only on open, move the open into a let%melange_only \
       function or the Melange branch of match%platform"]

  $ ./standalone.exe -impl input_pexp_open.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let f () =
    [%ocaml.error
      "Don't use native_only on open, move the open into the Native branch of \
       match%platform"]
