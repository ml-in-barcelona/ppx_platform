exception Melange_only of string

let message name = Printf.sprintf "'%s' is melange_only and ran in the native build." name

let fail_melange_only name =
  if Printexc.backtrace_status () then
    Printf.eprintf
      {|%s Call it only from Melange code: inside let%%melange_only, [%%melange_only ...] or the Melange branch of match%%platform.

Call stack:
%s
%!|}
      (message name)
      (Printexc.raw_backtrace_to_string (Printexc.get_callstack 8));
  raise (Melange_only name)

let () = Printexc.register_printer (function Melange_only name -> Some (message name) | _ -> None)
