let () =
  assert (Sample_native.target = "native");
  assert (Sample_native.only_native = "native");
  (match (Sample_native.click_handler [@alert "-browser_only"]) 1 with
  | _ -> assert false
  | exception Ppx_platform_runtime.Impossible_in_ssr _ -> ());
  assert (Sample_new_native.target = "native");
  assert (Sample_new_native.only_native = "native");
  match (Sample_new_native.click_handler [@alert "-melange_only"]) 1 with
  | _ -> assert false
  | exception Ppx_platform_runtime.Impossible_in_ssr _ -> ()
