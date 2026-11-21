open Ppxlib
module Builder = Ast_builder.Default

type target = Native | Js

let mode = ref Native
let melange_only = "melange_only"
let native_only = "native_only"
let is_platform_tag name = String.equal name melange_only || String.equal name native_only

(* Each removed name maps to its replacement. Without these errors, a removed attribute would be ignored silently and a
   removed extension would only report "Uninterpreted extension". They help migrations; remove them in 1.0.0. *)
let removed_cases = [ ("Server", "Native"); ("Client", "Melange") ]

let removed_message ~removed ~replacement =
  Printf.sprintf "[ppx_platform] %s was removed in 0.3.0, use %s" removed replacement

module Platform = struct
  let case_name case =
    match case.pc_lhs.ppat_desc with
    | Ppat_construct ({ txt = Lident name | Ldot (Lident "Runtime", (("Server" | "Client") as name)); _ }, _) ->
        Some name
    | _ -> None

  let collect_expressions ~loc first second =
    match (case_name first, case_name second) with
    | Some "Native", Some "Melange" -> Ok (first.pc_rhs, second.pc_rhs)
    | Some "Melange", Some "Native" -> Ok (second.pc_rhs, first.pc_rhs)
    | names ->
        let removed_case name =
          Option.bind name (fun name ->
              Option.map (fun replacement -> (name, replacement)) (List.assoc_opt name removed_cases))
        in
        let message =
          match List.find_map removed_case [ fst names; snd names ] with
          | Some (removed, replacement) ->
              removed_message ~removed:(Printf.sprintf "`%s`" removed) ~replacement:(Printf.sprintf "`%s`" replacement)
          | None -> "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange`"
        in
        Error [%expr [%ocaml.error [%e Builder.estring ~loc message]]]

  let switch_platform_requires_a_match ~loc =
    [%expr [%ocaml.error "[ppx_platform] switch%platform requires a match expression"]]

  let extract ~loc payload =
    match payload with
    | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] -> (
        match expression.pexp_desc with
        | Pexp_match (_expression, [ first; second ]) -> collect_expressions ~loc first second
        | _ -> Error (switch_platform_requires_a_match ~loc))
    | _ -> Error (switch_platform_requires_a_match ~loc)
end

let error_extension ~loc message =
  ({ txt = "ocaml.error"; loc }, PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc message) [] ])

module Melange_only = struct
  let location_name loc =
    let pos = loc.loc_start in
    Printf.sprintf "%s:%d:%d" pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol)

  let function_name pattern =
    match pattern.ppat_desc with Ppat_var { txt = name; _ } -> name | _ -> location_name pattern.ppat_loc

  let local_stubs = ref Scope.String_set.empty

  let error_only_works_on ~loc =
    [%expr
      [%ocaml.error
        "[ppx_platform] melange_only works on function definitions. For other cases, use switch%platform or feel free \
         to open an issue in https://github.com/ml-in-barcelona/ppx_platform."]]

  let unsupported_structure_item ~loc =
    Builder.pstr_extension ~loc
      (error_extension ~loc
         "[ppx_platform] [%%melange_only ...] supports one let binding. For other structure items, use \
          [@@melange_only].")
      []

  let remove_alert_only ~loc =
    Builder.attribute ~loc ~name:{ txt = "alert"; loc }
      ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc ("-" ^ melange_only)) [] ])

  let is_literal expr =
    match expr.pexp_desc with
    | Pexp_constant _ | Pexp_construct ({ txt = Lident ("true" | "false" | "()"); _ }, None) | Pexp_variant (_, None) ->
        true
    | _ -> false

  let rec plain_variable pattern =
    match pattern.ppat_desc with
    | Ppat_var name -> Some name
    | Ppat_constraint (pattern, _) -> plain_variable pattern
    | _ -> None

  let any_param ~loc = { pparam_loc = loc; pparam_desc = Pparam_val (Nolabel, None, Builder.ppat_any ~loc) }

  let stub_param ~outer_refs param =
    match param.pparam_desc with
    | Pparam_newtype _ -> None
    | Pparam_val (label, default, pattern) ->
        let default = match default with Some expr when is_literal expr -> default | _ -> None in
        let loc = pattern.ppat_loc in
        let pattern =
          match plain_variable pattern with
          | Some name when not (Scope.String_set.mem name.txt outer_refs) -> Builder.ppat_var ~loc name
          | _ -> Builder.ppat_any ~loc
        in
        Some { param with pparam_desc = Pparam_val (label, default, pattern) }

  let wrap_with_ignores ~loc ~kept_bindings ~outer_refs body =
    List.fold_right
      (fun name acc ->
        Builder.pexp_let ~loc Nonrecursive
          [
            Builder.value_binding ~loc ~pat:(Builder.ppat_any ~loc)
              ~expr:
                (if Scope.String_set.mem name !local_stubs then
                   { (Builder.evar ~loc name) with pexp_attributes = [ remove_alert_only ~loc ] }
                 else Builder.evar ~loc name);
          ]
          acc)
      (Scope.String_set.elements (Scope.String_set.union kept_bindings outer_refs))
      body

  let rec is_function expr =
    match expr.pexp_desc with
    | Pexp_function (params, _, body) -> (
        List.exists
          (fun param -> match param.pparam_desc with Pparam_val _ -> true | Pparam_newtype _ -> false)
          params
        || match body with Pfunction_cases _ -> true | Pfunction_body body -> is_function body)
    | Pexp_constraint (expr, _) | Pexp_coerce (expr, _, _) | Pexp_newtype (_, expr) -> is_function expr
    | _ -> false

  let fail ~loc ~outer_refs ~kept_bindings name =
    wrap_with_ignores ~loc ~kept_bindings ~outer_refs
      [%expr Ppx_platform.fail_melange_only [%e Builder.estring ~loc name]]

  let rec stub_body ~loc ~outer_refs ~kept_bindings name expr =
    match expr.pexp_desc with
    | Pexp_constraint (expr, _) | Pexp_coerce (expr, _, _) | Pexp_newtype (_, expr) ->
        stub_body ~loc ~outer_refs ~kept_bindings name expr
    | Pexp_function (params, _, body) -> (
        let params = List.filter_map (stub_param ~outer_refs) params in
        let kept_bindings =
          List.fold_left
            (fun acc param ->
              match param.pparam_desc with Pparam_val (_, _, pattern) -> Scope.add_pattern pattern acc | _ -> acc)
            kept_bindings params
        in
        let params, body =
          match body with
          | Pfunction_body body -> (params, stub_body ~loc ~outer_refs ~kept_bindings name body)
          | Pfunction_cases _ -> (params @ [ any_param ~loc ], fail ~loc ~outer_refs ~kept_bindings name)
        in
        match (params, body) with
        | [], body -> body
        | params, { pexp_desc = Pexp_function (more_params, None, body); pexp_attributes = []; _ } ->
            {
              (Builder.pexp_function ~loc (params @ more_params) None body) with
              pexp_attributes = expr.pexp_attributes;
            }
        | params, body ->
            {
              (Builder.pexp_function ~loc params None (Pfunction_body body)) with
              pexp_attributes = expr.pexp_attributes;
            })
    | _ -> fail ~loc ~outer_refs ~kept_bindings name

  let rec stub ~loc ~outer_refs name expr =
    match expr.pexp_desc with
    | Pexp_constraint (expr, _) | Pexp_coerce (expr, _, _) -> stub ~loc ~outer_refs name expr
    | Pexp_ident _ ->
        Some
          (Builder.pexp_function ~loc
             [ any_param ~loc ]
             None
             (Pfunction_body (fail ~loc ~outer_refs ~kept_bindings:Scope.String_set.empty name)))
    | _ when is_function expr -> Some (stub_body ~loc ~outer_refs ~kept_bindings:Scope.String_set.empty name expr)
    | _ -> None

  let alert_melange_only ~loc =
    let message =
      "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of \
       match%platform."
    in
    Builder.attribute ~loc ~name:{ txt = "alert"; loc }
      ~payload:
        (PStr
           [
             Builder.pstr_eval ~loc
               (Builder.pexp_apply ~loc (Builder.evar ~loc melange_only) [ (Nolabel, Builder.estring ~loc message) ])
               [];
           ])

  let add_alert ~loc =
    object
      inherit Ast_traverse.map as super

      method! pattern pattern =
        let pattern = super#pattern pattern in
        match pattern.ppat_desc with
        | Ppat_var _ | Ppat_alias _ ->
            { pattern with ppat_attributes = pattern.ppat_attributes @ [ alert_melange_only ~loc ] }
        | _ -> pattern
    end

  let warning_unused_value ~loc =
    Builder.attribute ~loc ~name:{ txt = "warning"; loc }
      ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc "-32") [] ])

  let stub_value_binding ~top_level ~locals vb =
    let attributes = List.filter (fun attr -> not (is_platform_tag attr.attr_name.txt)) vb.pvb_attributes in
    let pattern = vb.pvb_pat in
    let loc = pattern.ppat_loc in
    let outer_refs = Scope.collect_free_in_expr ~outer:locals vb.pvb_expr in
    match pattern with
    | [%pat? ()] ->
        {
          vb with
          pvb_expr = wrap_with_ignores ~loc ~kept_bindings:Scope.String_set.empty ~outer_refs [%expr ()];
          pvb_attributes = attributes;
        }
    | _ -> (
        match stub ~loc ~outer_refs (function_name pattern) vb.pvb_expr with
        | None -> Builder.value_binding ~loc ~pat:pattern ~expr:(error_only_works_on ~loc)
        | Some expr when top_level ->
            let expr = { expr with pexp_attributes = expr.pexp_attributes @ [ remove_alert_only ~loc ] } in
            let pat = (add_alert ~loc)#pattern pattern in
            { (Builder.value_binding ~loc ~pat ~expr) with pvb_attributes = warning_unused_value ~loc :: attributes }
        | Some expr ->
            {
              (Builder.value_binding ~loc ~pat:((add_alert ~loc)#pattern pattern) ~expr) with
              pvb_attributes = remove_alert_only ~loc :: attributes;
            })

  let mapper =
    object (self)
      inherit [Scope.String_set.t] Ast_traverse.map_with_context as super

      method! structure locals items =
        snd
          (List.fold_left_map
             (fun locals item ->
               (Scope.String_set.diff locals (Scope.bindings_of_structure_item item), self#structure_item locals item))
             locals items)

      method! structure_item locals item =
        match item.pstr_desc with
        | Pstr_value (Recursive, vbs) ->
            let locals = Scope.add_value_bindings vbs locals in
            { item with pstr_desc = Pstr_value (Recursive, List.map (self#value_binding locals) vbs) }
        | Pstr_extension (({ txt; _ }, payload), _) when String.equal txt melange_only -> (
            let loc = item.pstr_loc in
            match payload with
            | PStr [ { pstr_desc = Pstr_value (rec_flag, vbs); _ } ] ->
                let locals =
                  match rec_flag with Recursive -> Scope.add_value_bindings vbs locals | Nonrecursive -> locals
                in
                let rewrite =
                  match !mode with
                  | Js -> self#value_binding locals
                  | Native -> stub_value_binding ~top_level:true ~locals
                in
                Builder.pstr_value ~loc rec_flag (List.map rewrite vbs)
            | _ -> unsupported_structure_item ~loc)
        | _ -> super#structure_item locals item

      method! expression locals expr =
        match expr.pexp_desc with
        | Pexp_extension ({ txt = "platform"; _ }, payload) -> (
            let loc = expr.pexp_loc in
            match Platform.extract ~loc payload with
            | Ok (server_expr, client_expr) ->
                let kept_expr, discarded_expr =
                  match !mode with Js -> (client_expr, server_expr) | Native -> (server_expr, client_expr)
                in
                let kept_expr' = self#expression locals kept_expr in
                let outer_refs =
                  Scope.String_set.diff
                    (Scope.collect_free_in_expr ~outer:locals discarded_expr)
                    (Scope.collect_free_in_expr ~outer:locals kept_expr')
                in
                let result = wrap_with_ignores ~loc ~kept_bindings:Scope.String_set.empty ~outer_refs kept_expr' in
                { result with pexp_attributes = result.pexp_attributes @ expr.pexp_attributes }
            | Error error_msg_expr -> error_msg_expr)
        | Pexp_extension ({ txt; _ }, payload) when String.equal txt melange_only -> (
            let loc = expr.pexp_loc in
            match (!mode, payload) with
            | Js, PStr [ { pstr_desc = Pstr_eval (payload, []); _ } ] -> self#expression locals payload
            | Native, PStr [ { pstr_desc = Pstr_eval ({ pexp_desc = Pexp_let (rec_flag, vbs, body); _ }, []); _ } ] ->
                let vb_locals =
                  match rec_flag with Recursive -> Scope.add_value_bindings vbs locals | Nonrecursive -> locals
                in
                let vbs' = List.map (stub_value_binding ~top_level:false ~locals:vb_locals) vbs in
                local_stubs := Scope.add_value_bindings vbs !local_stubs;
                let body' = self#expression (Scope.add_value_bindings vbs locals) body in
                Builder.pexp_let ~loc rec_flag vbs' body'
            | Native, PStr [ { pstr_desc = Pstr_eval (payload, []); _ } ] -> (
                let outer_refs = Scope.collect_free_in_expr ~outer:locals payload in
                match stub ~loc ~outer_refs (location_name loc) payload with
                | Some stubbed -> stubbed
                | None -> error_only_works_on ~loc)
            | _ -> error_only_works_on ~loc)
        | Pexp_let (Nonrecursive, vbs, body) ->
            let vbs' = List.map (self#value_binding locals) vbs in
            let body' = self#expression (Scope.add_value_bindings vbs locals) body in
            { expr with pexp_desc = Pexp_let (Nonrecursive, vbs', body') }
        | Pexp_let (Recursive, vbs, body) ->
            let locals' = Scope.add_value_bindings vbs locals in
            let vbs' = List.map (self#value_binding locals') vbs in
            let body' = self#expression locals' body in
            { expr with pexp_desc = Pexp_let (Recursive, vbs', body') }
        | Pexp_letop { let_; ands; body } ->
            let map_bop bop = { bop with pbop_exp = self#expression locals bop.pbop_exp } in
            let let_' = map_bop let_ in
            let ands' = List.map map_bop ands in
            let locals' = List.fold_left (fun s bop -> Scope.add_pattern bop.pbop_pat s) locals (let_ :: ands) in
            let body' = self#expression locals' body in
            { expr with pexp_desc = Pexp_letop { let_ = let_'; ands = ands'; body = body' } }
        | Pexp_function (params, constraint_, body) ->
            let rev_params, locals' =
              List.fold_left
                (fun (acc, s) param ->
                  match param.pparam_desc with
                  | Pparam_val (lbl, default_opt, pat) ->
                      let default_opt' = Option.map (self#expression s) default_opt in
                      let s' = Scope.add_pattern pat s in
                      ({ param with pparam_desc = Pparam_val (lbl, default_opt', pat) } :: acc, s')
                  | Pparam_newtype _ -> (param :: acc, s))
                ([], locals) params
            in
            let body' =
              match body with
              | Pfunction_body e -> Pfunction_body (self#expression locals' e)
              | Pfunction_cases (cases, loc, attrs) -> Pfunction_cases (self#cases locals' cases, loc, attrs)
            in
            { expr with pexp_desc = Pexp_function (List.rev rev_params, constraint_, body') }
        | Pexp_for (pat, e1, e2, dir, body) ->
            let e1' = self#expression locals e1 in
            let e2' = self#expression locals e2 in
            let body' = self#expression (Scope.add_pattern pat locals) body in
            { expr with pexp_desc = Pexp_for (pat, e1', e2', dir, body') }
        | Pexp_open (({ popen_expr = { pmod_desc = Pmod_structure items; _ }; _ } as od), body) ->
            let od' = self#open_declaration locals od in
            let body' = self#expression (Scope.String_set.diff locals (Scope.structure_bindings items)) body in
            { expr with pexp_desc = Pexp_open (od', body') }
        | _ -> super#expression locals expr

      method! class_structure locals cls_str =
        let locals' = Scope.String_set.union locals (Scope.class_structure_bindings cls_str) in
        let map_field field =
          match field.pcf_desc with
          | Pcf_val (name, mutable_flag, Cfk_concrete (override, init)) ->
              {
                field with
                pcf_desc = Pcf_val (name, mutable_flag, Cfk_concrete (override, self#expression locals init));
              }
          | _ -> self#class_field locals' field
        in
        { cls_str with pcstr_fields = List.map map_field cls_str.pcstr_fields }

      method! case locals case =
        let locals' = Scope.add_pattern case.pc_lhs locals in
        {
          case with
          pc_guard = Option.map (self#expression locals') case.pc_guard;
          pc_rhs = self#expression locals' case.pc_rhs;
        }

      method! class_expr locals ce =
        match ce.pcl_desc with
        | Pcl_fun (lbl, default_opt, pat, body) ->
            let default_opt' = Option.map (self#expression locals) default_opt in
            let body' = self#class_expr (Scope.add_pattern pat locals) body in
            { ce with pcl_desc = Pcl_fun (lbl, default_opt', pat, body') }
        | Pcl_let (Nonrecursive, vbs, body) ->
            let vbs' = List.map (self#value_binding locals) vbs in
            let body' = self#class_expr (Scope.add_value_bindings vbs locals) body in
            { ce with pcl_desc = Pcl_let (Nonrecursive, vbs', body') }
        | Pcl_let (Recursive, vbs, body) ->
            let locals' = Scope.add_value_bindings vbs locals in
            let vbs' = List.map (self#value_binding locals') vbs in
            let body' = self#class_expr locals' body in
            { ce with pcl_desc = Pcl_let (Recursive, vbs', body') }
        | _ -> super#class_expr locals ce
    end

  let traverse structure =
    local_stubs := Scope.String_set.empty;
    mapper#structure Scope.String_set.empty structure
end

module Preprocess = struct
  (* This module is heavily based on leostera `config.ml` PPX:
     https://github.com/ocaml-sys/config.ml/blob/d248987cc1795de99d3735c06635dbd355d4d642/config/cfg_ppx.ml*)

  let eval_attr attr =
    let name = attr.attr_name.txt in
    match !mode with
    | Native when String.equal name melange_only -> `drop
    | Js when String.equal name native_only -> `drop
    | _ -> `keep

  let dropped_name attrs =
    match List.find_opt (fun attr -> eval_attr attr = `drop) attrs with Some attr -> attr.attr_name.txt | None -> ""

  let expression_error ~loc attrs =
    [%expr
      [%ocaml.error
        [%e
          Builder.estring ~loc
            (Printf.sprintf "Don't use %s on expressions, use switch%%platform instead" (dropped_name attrs))]]]

  let evaluated : (Location.t, unit) Hashtbl.t = Hashtbl.create 16

  let should_keep attrs =
    List.iter (fun attr -> if is_platform_tag attr.attr_name.txt then Hashtbl.replace evaluated attr.attr_loc ()) attrs;
    if List.exists (fun attr -> eval_attr attr = `drop) attrs then `drop else `keep

  let floating_error ~loc attr =
    error_extension ~loc
      (Printf.sprintf "[ppx_platform] [@@@%s] works only as the first item of a structure or a signature"
         attr.attr_name.txt)

  let rec should_keep_many list fn =
    match list with
    | [] -> `keep
    | item :: list -> if should_keep (fn item) = `drop then `drop else should_keep_many list fn

  let apply_config_on_types (tds : type_declaration list) =
    List.filter_map
      (fun td ->
        match td with
        | {
         ptype_kind = Ptype_abstract;
         ptype_manifest = Some ({ ptyp_desc = Ptyp_variant (rows, closed_flag, labels); _ } as manifest);
         _;
        } ->
            let rows =
              List.filter_map (fun row -> if should_keep row.prf_attributes = `keep then Some row else None) rows
            in

            if rows = [] then None
            else
              Some
                { td with ptype_manifest = Some { manifest with ptyp_desc = Ptyp_variant (rows, closed_flag, labels) } }
        | { ptype_kind = Ptype_variant cstrs; _ } ->
            let cstrs =
              List.filter_map (fun cstr -> if should_keep cstr.pcd_attributes = `keep then Some cstr else None) cstrs
            in

            if cstrs = [] then None else Some { td with ptype_kind = Ptype_variant cstrs }
        | { ptype_kind = Ptype_record labels; _ } ->
            let labels =
              List.filter_map
                (fun label -> if should_keep label.pld_attributes = `keep then Some label else None)
                labels
            in

            if labels = [] then None else Some { td with ptype_kind = Ptype_record labels }
        | _ -> Some td)
      tds

  let apply_config_on_structure_item stri =
    match stri.pstr_desc with
    | Pstr_typext { ptyext_attributes = attrs; _ }
    | Pstr_modtype { pmtd_attributes = attrs; _ }
    | Pstr_open { popen_attributes = attrs; _ }
    | Pstr_include { pincl_attributes = attrs; _ }
    | Pstr_exception { ptyexn_attributes = attrs; _ }
    | Pstr_primitive { pval_attributes = attrs; _ }
    | Pstr_eval (_, attrs)
    | Pstr_module { pmb_attributes = attrs; _ } ->
        if should_keep attrs = `keep then Some stri else None
    | Pstr_value (_, vbs) -> if should_keep_many vbs (fun vb -> vb.pvb_attributes) = `keep then Some stri else None
    | Pstr_type (recflag, tds) ->
        if should_keep_many tds (fun td -> td.ptype_attributes) = `keep then
          let tds = apply_config_on_types tds in
          Some { stri with pstr_desc = Pstr_type (recflag, tds) }
        else None
    | Pstr_recmodule md -> if should_keep_many md (fun md -> md.pmb_attributes) = `keep then Some stri else None
    | Pstr_class cds -> if should_keep_many cds (fun cd -> cd.pci_attributes) = `keep then Some stri else None
    | Pstr_class_type ctds -> if should_keep_many ctds (fun ctd -> ctd.pci_attributes) = `keep then Some stri else None
    | Pstr_attribute attr when is_platform_tag attr.attr_name.txt ->
        Some (Builder.pstr_extension ~loc:attr.attr_loc (floating_error ~loc:attr.attr_loc attr) [])
    | Pstr_extension _ | Pstr_attribute _ -> Some stri

  let apply_config_on_signature_item sigi =
    match sigi.psig_desc with
    | Psig_typext { ptyext_attributes = attrs; _ }
    | Psig_modtype { pmtd_attributes = attrs; _ }
    | Psig_open { popen_attributes = attrs; _ }
    | Psig_include { pincl_attributes = attrs; _ }
    | Psig_exception { ptyexn_attributes = attrs; _ }
    | Psig_value { pval_attributes = attrs; _ }
    | Psig_modtypesubst { pmtd_attributes = attrs; _ }
    | Psig_modsubst { pms_attributes = attrs; _ }
    | Psig_module { pmd_attributes = attrs; _ } ->
        if should_keep attrs = `keep then Some sigi else None
    | Psig_typesubst tds ->
        if should_keep_many tds (fun td -> td.ptype_attributes) = `keep then
          let tds = apply_config_on_types tds in
          Some { sigi with psig_desc = Psig_typesubst tds }
        else None
    | Psig_type (recflag, tds) ->
        if should_keep_many tds (fun td -> td.ptype_attributes) = `keep then
          let tds = apply_config_on_types tds in
          Some { sigi with psig_desc = Psig_type (recflag, tds) }
        else None
    | Psig_recmodule md -> if should_keep_many md (fun md -> md.pmd_attributes) = `keep then Some sigi else None
    | Psig_class cds -> if should_keep_many cds (fun cd -> cd.pci_attributes) = `keep then Some sigi else None
    | Psig_class_type ctds -> if should_keep_many ctds (fun ctd -> ctd.pci_attributes) = `keep then Some sigi else None
    | Psig_attribute attr when is_platform_tag attr.attr_name.txt ->
        Some (Builder.psig_extension ~loc:attr.attr_loc (floating_error ~loc:attr.attr_loc attr) [])
    | Psig_extension _ | Psig_attribute _ -> Some sigi

  let case_pattern =
    object
      inherit Ast_traverse.map as super

      method! pattern pat =
        let pat = super#pattern pat in
        if should_keep pat.ppat_attributes = `keep then pat
        else
          let loc = pat.ppat_loc in
          Builder.ppat_extension ~loc
            (error_extension ~loc
               (Printf.sprintf "Don't use %s on match case patterns, use switch%%platform instead"
                  (dropped_name pat.ppat_attributes)))
    end

  let traverse =
    object (self : Ast_traverse.map)
      inherit Ast_traverse.map as super

      method! structure str =
        let str =
          List.filter_map
            (fun item ->
              let item' = self#structure_item item in
              match (item.pstr_desc, item'.pstr_desc) with
              | Pstr_extension ((_, PStr (_ :: _)), _), Pstr_extension ((_, PStr []), _) -> None
              | _ -> Some item')
            str
        in
        match str with
        | { pstr_desc = Pstr_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then List.filter_map apply_config_on_structure_item rest else []
        | str -> List.filter_map apply_config_on_structure_item str

      method! structure_item stri =
        match (!mode, stri.pstr_desc) with
        | Native, Pstr_extension (({ txt; _ }, _), _) when String.equal txt melange_only -> stri
        | _ -> super#structure_item stri

      method! signature sigi =
        let sigi = super#signature sigi in
        match sigi with
        | { psig_desc = Psig_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then List.filter_map apply_config_on_signature_item rest else []
        | _ -> List.filter_map apply_config_on_signature_item sigi

      method! expression expr =
        match (!mode, expr.pexp_desc) with
        | ( Native,
            Pexp_extension
              ( ({ txt; _ } as ext_name),
                PStr
                  [
                    ({
                       pstr_desc =
                         Pstr_eval (({ pexp_desc = Pexp_let (rec_flag, vbs, body); _ } as let_expr), eval_attrs);
                       _;
                     } as str_item);
                  ] ) )
          when String.equal txt melange_only ->
            let body = self#expression body in
            {
              expr with
              pexp_desc =
                Pexp_extension
                  ( ext_name,
                    PStr
                      [
                        {
                          str_item with
                          pstr_desc =
                            Pstr_eval ({ let_expr with pexp_desc = Pexp_let (rec_flag, vbs, body) }, eval_attrs);
                        };
                      ] );
            }
        | Native, Pexp_extension ({ txt; _ }, _) when String.equal txt melange_only -> expr
        | _, Pexp_extension (({ txt = "platform"; _ } as ext_name), payload) -> (
            if should_keep expr.pexp_attributes = `drop then expression_error ~loc:expr.pexp_loc expr.pexp_attributes
            else
              match payload with
              | PStr
                  [
                    ({
                       pstr_desc =
                         Pstr_eval
                           (({ pexp_desc = Pexp_match (scrutinee, [ first; second ]); _ } as match_expr), eval_attrs);
                       _;
                     } as str_item);
                  ] ->
                  let cases' =
                    match (Platform.case_name first, Platform.case_name second) with
                    | Some "Native", Some "Melange" -> (
                        match !mode with
                        | Native -> [ { first with pc_rhs = self#expression first.pc_rhs }; second ]
                        | Js -> [ first; { second with pc_rhs = self#expression second.pc_rhs } ])
                    | Some "Melange", Some "Native" -> (
                        match !mode with
                        | Native -> [ first; { second with pc_rhs = self#expression second.pc_rhs } ]
                        | Js -> [ { first with pc_rhs = self#expression first.pc_rhs }; second ])
                    | _ -> [ first; second ]
                  in
                  {
                    expr with
                    pexp_desc =
                      Pexp_extension
                        ( ext_name,
                          PStr
                            [
                              {
                                str_item with
                                pstr_desc =
                                  Pstr_eval ({ match_expr with pexp_desc = Pexp_match (scrutinee, cases') }, eval_attrs);
                              };
                            ] );
                  }
              | _ -> expr)
        | _, Pexp_open (od, _) when should_keep expr.pexp_attributes = `drop || should_keep od.popen_attributes = `drop
          ->
            expression_error ~loc:expr.pexp_loc (expr.pexp_attributes @ od.popen_attributes)
        | _ -> (
            let expr = super#expression expr in
            let loc = expr.pexp_loc in
            match expr.pexp_desc with
            | Pexp_let (_, [ { pvb_attributes = attrs; _ } ], _) ->
                let loc = expr.pexp_loc in
                if should_keep attrs = `keep then expr else expression_error ~loc attrs
            | _ -> if should_keep expr.pexp_attributes = `keep then expr else expression_error ~loc expr.pexp_attributes
            )

      method! case case =
        {
          pc_lhs = case_pattern#pattern case.pc_lhs;
          pc_guard = Option.map self#expression case.pc_guard;
          pc_rhs = self#expression case.pc_rhs;
        }

      method! pattern pat =
        match pat.ppat_desc with
        | Ppat_constraint (inner_pat, _) ->
            let loc = pat.ppat_loc in
            if should_keep inner_pat.ppat_attributes = `keep then super#pattern pat else [%pat? _]
        | _ ->
            let pat = super#pattern pat in
            let loc = pat.ppat_loc in
            if should_keep pat.ppat_attributes = `keep then pat else [%pat? _]
    end

  let structure str =
    Hashtbl.reset evaluated;
    traverse#structure str

  let signature sigi =
    Hashtbl.reset evaluated;
    traverse#signature sigi

  let remove_evaluated =
    object
      inherit Ast_traverse.map as super

      method! attributes attrs =
        let keep attr =
          if not (is_platform_tag attr.attr_name.txt) then true
          else if Hashtbl.mem evaluated attr.attr_loc then false
          else
            Location.raise_errorf ~loc:attr.attr_loc
              "[ppx_platform] [@%s] is not supported here. Use it on a structure or signature item, a constructor or \
               record field of a type definition, a polymorphic variant tag, a pattern or an expression."
              attr.attr_name.txt
        in
        super#attributes (List.filter keep attrs)
    end
end

module Removed = struct
  let extension_rule context ~error =
    Context_free.Rule.extension
      (Extension.V3.declare "browser_only" context Ast_pattern.__ (fun ~ctxt _payload ->
           let loc = Expansion_context.Extension.extension_point_loc ctxt in
           error ~loc (removed_message ~removed:"%browser_only" ~replacement:"%melange_only")))

  let rules =
    [
      extension_rule Extension.Context.expression ~error:(fun ~loc message ->
          [%expr [%ocaml.error [%e Builder.estring ~loc message]]]);
      extension_rule Extension.Context.structure_item ~error:(fun ~loc message ->
          [%stri [%%ocaml.error [%e Builder.estring ~loc message]]]);
    ]

  let attribute_replacement attr =
    match (attr.attr_name.txt, attr.attr_payload) with
    | "browser_only", _ -> Some ("[@browser_only]", "[@melange_only]")
    | "platform", PStr [ { pstr_desc = Pstr_eval ({ pexp_desc = Pexp_ident { txt = Lident "js"; _ }; _ }, []); _ } ] ->
        Some ("[@platform js]", "[@melange_only]")
    | "platform", PStr [ { pstr_desc = Pstr_eval ({ pexp_desc = Pexp_ident { txt = Lident "native"; _ }; _ }, []); _ } ]
      ->
        Some ("[@platform native]", "[@native_only]")
    | "platform", _ -> Some ("[@platform ...]", "[@melange_only] or [@native_only]")
    | _ -> None

  (* An attribute can't carry an error node, so this one stops at the first removed attribute. *)
  let reject =
    object
      inherit Ast_traverse.iter as super

      method! attribute attr =
        match attribute_replacement attr with
        | Some (removed, replacement) ->
            Location.raise_errorf ~loc:attr.attr_loc "%s" (removed_message ~removed ~replacement)
        | None -> super#attribute attr
    end
end

let () =
  Driver.add_arg "-js" (Unit (fun () -> mode := Js)) ~doc:"preprocess for js build";
  let instrument =
    Driver.Instrument.V2.make ~position:Before (fun _ structure ->
        Removed.reject#structure structure;
        let structure = Preprocess.structure structure in
        Preprocess.remove_evaluated#structure (Melange_only.traverse structure))
  in
  Driver.V2.register_transformation "ppx_platform" ~rules:Removed.rules ~instrument ~intf:(fun _ signature ->
      Removed.reject#signature signature;
      Preprocess.remove_evaluated#signature (Preprocess.signature signature))
