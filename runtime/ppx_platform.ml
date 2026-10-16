exception Melange_only of string

let message name = Printf.sprintf "'%s' is melange_only and ran in the native build." name

let fail_melange_only name =
  if Printexc.backtrace_status () then
    prerr_string (message name ^ "\n" ^ Printexc.raw_backtrace_to_string (Printexc.get_callstack 8));
  raise (Melange_only name)

let () = Printexc.register_printer (function Melange_only name -> Some (message name) | _ -> None)
