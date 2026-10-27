let () =
  assert (Sample.target = "native");
  assert (Sample.only_native = "native");
  assert (Sample.cookie_mode = "ocaml");
  assert (Sample_swapped.target = "native");
  assert (Sample_swapped.cookie_mode = "ocaml");
  match (Sample.click_handler [@alert "-melange_only"]) 1 with
  | _ -> assert false
  | exception Ppx_platform.Melange_only _ -> ()
