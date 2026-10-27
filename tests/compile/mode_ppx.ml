open Ppxlib

let mode = ref "absent"

let () =
  Driver.Cookies.add_handler (fun cookies ->
      Option.iter (fun value -> mode := value) (Driver.Cookies.get cookies "compilation-mode" Ast_pattern.(estring __)));
  Extension.declare "compilation_mode" Extension.Context.expression
    Ast_pattern.(pstr nil)
    (fun ~loc ~path:_ -> Ast_builder.Default.estring ~loc !mode)
  |> fun ext -> Driver.register_transformation "mode_ppx" ~extensions:[ ext ]
