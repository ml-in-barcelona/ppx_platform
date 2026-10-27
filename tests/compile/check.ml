let () =
  assert (Sample.target = "native");
  assert (Sample.only_native = "native");
  match (Sample.click_handler [@alert "-melange_only"]) 1 with
  | _ -> assert false
  | exception Ppx_platform.Melange_only _ -> ()
