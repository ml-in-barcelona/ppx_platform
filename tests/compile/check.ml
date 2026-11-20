let () =
  assert (Sample_native.target = "native");
  assert (Sample_native.only_native = "native");
  match (Sample_native.click_handler [@alert "-melange_only"]) 1 with
  | _ -> assert false
  | exception Ppx_platform.Melange_only _ -> ()

let raises_melange_only name f =
  match f () with _ -> assert false | exception Ppx_platform.Melange_only n -> assert (n = name)

let () =
  let node : Dom_native.node = Obj.magic () in
  raises_melange_only "owner_document" (fun () -> Dom_native.owner_document node);
  raises_melange_only "set_attribute" (fun () -> Dom_native.set_attribute node ~name:"id" "x");
  raises_melange_only "set_title" (fun () -> Dom_native.set_title "x")
