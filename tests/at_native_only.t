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

With the melange compilation-mode cookie it picks the block with `[@@melange_only]`

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  module X = struct
    include struct
      type t = Js.Json.t
  
      let a = 2 + 2
    end [@@melange_only]
  end

Without the cookie, it picks the block with `[@@native_only]`

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  module X = struct
    include struct
      type t = Js.Json.t
  
      let a = 4 + 4
    end [@@native_only]
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

With the melange compilation-mode cookie it picks the block with `[@@melange_only]`

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Js.Json.t
  end [@@melange_only]

Without the cookie, it picks the block with `[@@native_only]`

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = string
  end [@@native_only]

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

  $ ./standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Js.Json.t
  end [@@melange_only]
  
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
  [@@native_only]

  $ ./standalone.exe -impl input_module.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  module M = struct
    let x = 42
  end
  [@@melange_only]

Pstr_value

  $ cat > input_let.ml << EOF
  > let x = 42 [@@melange_only]
  > let y = 44 [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_let.ml | ocamlformat - --enable-outside-detected-project --impl
  let y = 44 [@@native_only]

  $ ./standalone.exe -impl input_let.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let x = 42 [@@melange_only]

Pstr_open

  $ cat > input_open.ml << EOF
  > open Printf [@@melange_only]
  > open List [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_open.ml | ocamlformat - --enable-outside-detected-project --impl
  open List [@@native_only]

  $ ./standalone.exe -impl input_open.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  open Printf [@@melange_only]

Pstr_exception

  $ cat > input_exception.ml << EOF
  > exception MyException of string [@@melange_only]
  > exception AnotherException of int [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_exception.ml | ocamlformat - --enable-outside-detected-project --impl
  exception AnotherException of int [@@native_only]

  $ ./standalone.exe -impl input_exception.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  exception MyException of string [@@melange_only]

Pstr_primitive

  $ cat > input_primitive.ml << EOF
  > external add : int -> int -> int = "caml_add_int" [@@melange_only]
  > external subtract : int -> int -> int = "caml_subtract_int" [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_primitive.ml | ocamlformat - --enable-outside-detected-project --impl
  external subtract : int -> int -> int = "caml_subtract_int" [@@native_only]

  $ ./standalone.exe -impl input_primitive.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  external add : int -> int -> int = "caml_add_int" [@@melange_only]

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
    3 [@@native_only]
  end

  $ ./standalone.exe -impl input_primitive.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  include struct
    2 [@@melange_only]
  end
  
  include struct end

Pstr_type

  $ cat > input_type.ml << EOF
  > type point = { x : int; y : int } [@@melange_only]
  > type color = Red | Green | Blue [@@native_only]
  > EOF

  $ ./standalone.exe -impl input_type.ml | ocamlformat - --enable-outside-detected-project --impl
  type color = Red | Green | Blue [@@native_only]

  $ ./standalone.exe -impl input_type.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  type point = { x : int; y : int } [@@melange_only]

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
  [@@native_only]

  $ ./standalone.exe -impl input_recmodule.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  module rec M = struct
    let x = 42
  end
  [@@melange_only]

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
    end [@@native_only]

  $ ./standalone.exe -impl input_class.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  class virtual ['a] base x =
    object
      method get = x
    end [@@melange_only]

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
  end [@@native_only]

  $ ./standalone.exe -impl input_class_type.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  class type base = object
    method get : int
  end [@@melange_only]
