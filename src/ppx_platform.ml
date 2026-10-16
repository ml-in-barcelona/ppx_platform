open Ppxlib
module Builder = Ast_builder.Default

type target = Native | Js

let mode = ref Native
let melange_only = "melange_only"
let native_only = "native_only"
let is_platform_tag name = String.equal name melange_only || String.equal name native_only

module Platform = struct
  let pattern = Ast_pattern.(__')

  let case_name case =
    match case.pc_lhs.ppat_desc with Ppat_construct ({ txt = Lident name; _ }, _) -> Some name | _ -> None

  let collect_expressions ~loc first second =
    match (case_name first, case_name second) with
    | Some "Native", Some "Melange" -> Ok (first.pc_rhs, second.pc_rhs)
    | Some "Melange", Some "Native" -> Ok (second.pc_rhs, first.pc_rhs)
    | _ -> Error [%expr [%ocaml.error "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange`"]]

  let switch_platform_requires_a_match ~loc =
    [%expr [%ocaml.error "[ppx_platform] switch%platform requires a match expression"]]

  let handler ~ctxt:_ { txt = payload; loc } =
    match payload with
    | PStr [ { pstr_desc = Pstr_eval (expression, _); _ } ] -> (
        match expression.pexp_desc with
        | Pexp_match (_expression, cases) -> (
            match cases with
            | [ first; second ] -> (
                match collect_expressions ~loc first second with
                | Ok (server_expr, client_expr) -> (
                    match !mode with
                    (* When it's -js keep the client_expr *)
                    | Js -> client_expr
                    (* When it's isn't -js keep the server_expr *)
                    | Native -> server_expr)
                | Error error_msg_expr -> error_msg_expr)
            | _ -> switch_platform_requires_a_match ~loc)
        | _ -> switch_platform_requires_a_match ~loc)
    | _ -> switch_platform_requires_a_match ~loc

  let rule = Context_free.Rule.extension (Extension.V3.declare "platform" Extension.Context.expression pattern handler)
end

let remove_type_constraint pattern =
  match pattern with { ppat_desc = Ppat_constraint (pattern, _); _ } -> pattern | _ -> pattern

let rec last_expr_to_raise_impossible ~loc original_name expr =
  match expr.pexp_desc with
  | Pexp_constraint (expr, _) -> last_expr_to_raise_impossible ~loc original_name expr
  | Pexp_function
      ({ pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _rest, _, Pfunction_body expression)
    ->
      let new_fun_pattern = remove_type_constraint fun_pattern in
      let fn =
        Builder.pexp_fun ~loc arg_label None new_fun_pattern
          (last_expr_to_raise_impossible ~loc original_name expression)
      in
      { fn with pexp_attributes = expr.pexp_attributes }
  | _ -> [%expr Ppx_platform_runtime.fail_impossible_action_in_ssr [%e Builder.estring ~loc original_name]]

module Melange_only = struct
  let get_function_name pattern = match pattern with Ppat_var { txt = name; _ } -> name | _ -> "<unkwnown>"

  let error_only_works_on ~loc =
    [%expr
      [%ocaml.error
        "[ppx_platform] melange_only works on function definitions. For other cases, use switch%platform or feel free \
         to open an issue in https://github.com/ml-in-barcelona/ppx_platform."]]

  let remove_alert_only ~loc =
    Builder.attribute ~loc ~name:{ txt = "alert"; loc }
      ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc ("-" ^ melange_only)) [] ])

  let melange_only_fun ~loc arg_label pattern expression =
    let stringified = Ppxlib.Pprintast.string_of_expression expression in
    let message = Builder.estring ~loc stringified in
    let fn =
      Builder.pexp_fun ~loc arg_label None pattern
        [%expr Ppx_platform_runtime.fail_impossible_action_in_ssr [%e message]]
    in
    { fn with pexp_attributes = expression.pexp_attributes }

  let melange_only_value_binding pattern expression =
    let loc = pattern.ppat_loc in
    match pattern with
    | [%pat? ()] -> Builder.value_binding ~loc ~pat:pattern ~expr:[%expr ()]
    | _ -> (
        match expression.pexp_desc with
        | Pexp_constraint
            ( { pexp_desc = Pexp_function ({ pparam_desc = Pparam_val _; _ } :: _, _, Pfunction_body _); _ },
              _type_constraint ) ->
            let function_name = get_function_name pattern.ppat_desc in
            let expr = last_expr_to_raise_impossible ~loc function_name expression in
            let vb = Builder.value_binding ~loc ~pat:pattern ~expr in
            { vb with pvb_attributes = [ remove_alert_only ~loc ] }
        | Pexp_function ({ pparam_desc = Pparam_val _; _ } :: _, _, Pfunction_body _) ->
            let function_name = get_function_name pattern.ppat_desc in
            let expr = last_expr_to_raise_impossible ~loc function_name expression in
            let vb = Builder.value_binding ~loc ~pat:pattern ~expr in
            { vb with pvb_attributes = [ remove_alert_only ~loc ] }
        | _ -> Builder.value_binding ~loc ~pat:pattern ~expr:(error_only_works_on ~loc))

  let extractor_single_payload = Ast_pattern.(single_expr_payload __)

  let expression_handler ~ctxt payload =
    let replace_fun_body_with_raise_impossible ~loc pexp_desc =
      match pexp_desc with
      | Pexp_constraint
          ( {
              pexp_desc =
                Pexp_function
                  ( { pparam_desc = Pparam_val (arg_label, _arg_expression, pattern); _ } :: _,
                    _,
                    Pfunction_body expression );
              _;
            },
            type_constraint ) ->
          let fn = melange_only_fun ~loc arg_label pattern expression in
          Builder.pexp_constraint ~loc { fn with pexp_attributes = expression.pexp_attributes } type_constraint
      | Pexp_function
          ({ pparam_desc = Pparam_val (arg_label, _arg_expression, pattern); _ } :: _, _, Pfunction_body expr) ->
          let function_name = get_function_name pattern.ppat_desc in
          let new_fun_pattern = remove_type_constraint pattern in
          Builder.pexp_fun ~loc arg_label None new_fun_pattern (last_expr_to_raise_impossible ~loc function_name expr)
      | Pexp_let (rec_flag, value_bindings, expression) ->
          let pexp_let =
            Builder.pexp_let ~loc rec_flag
              (List.map (fun binding -> melange_only_value_binding binding.pvb_pat binding.pvb_expr) value_bindings)
              expression
          in
          [%expr [%e pexp_let]]
      | _ -> error_only_works_on ~loc
    in
    match !mode with
    | Js -> payload
    | Native ->
        let loc = Expansion_context.Extension.extension_point_loc ctxt in
        replace_fun_body_with_raise_impossible ~loc payload.pexp_desc

  let expression_rule =
    Context_free.Rule.extension
      (Extension.V3.declare melange_only Extension.Context.expression extractor_single_payload expression_handler)

  (* Generates a structure_item with a value binding with a pattern and an expression with all the alerts and warnings *)
  let make_vb_with_melange_only ~loc ?type_constraint pattern expression =
    let alert_message =
      "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of \
       match%platform."
    in
    let alert =
      Builder.attribute ~loc ~name:{ txt = "alert"; loc }
        ~payload:
          (PStr
             [
               Builder.pstr_eval ~loc
                 (Builder.pexp_apply ~loc (Builder.evar ~loc melange_only)
                    [ (Nolabel, Builder.estring ~loc alert_message) ])
                 [];
             ])
    in
    let expression = { expression with pexp_attributes = expression.pexp_attributes @ [ remove_alert_only ~loc ] } in
    let pattern =
      match type_constraint with
      | Some type_constraint ->
          Builder.ppat_constraint ~loc pattern { type_constraint with ptyp_attributes = [ alert ] }
      | None -> { pattern with ppat_attributes = [ alert ] }
    in
    [%stri let[@warning "-27-32"] [%p pattern] = [%e expression]]

  let extractor_vb =
    let open Ast_pattern in
    let extractor_in_let = pstr_value __ (value_binding ~pat:__ ~expr:__ ~constraint_:drop ^:: nil) in
    pstr @@ extractor_in_let ^:: nil

  let structure_item_handler ~ctxt rec_flag pattern expression =
    let loc = Expansion_context.Extension.extension_point_loc ctxt in
    let do_nothing rec_flag =
      match rec_flag with
      | Recursive -> [%stri let rec [%p pattern] = [%e expression]]
      | Nonrecursive -> [%stri let [%p pattern] = [%e expression]]
    in

    let add_melange_only_alert expression =
      match expression.pexp_desc with
      | Pexp_constraint
          ( {
              pexp_desc =
                Pexp_function
                  ( { pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _,
                    _,
                    Pfunction_body expr );
              _;
            },
            type_constraint ) ->
          let original_function_name = get_function_name pattern.ppat_desc in
          let new_fun_pattern = remove_type_constraint fun_pattern in
          let fn =
            Builder.pexp_fun ~loc arg_label None new_fun_pattern
              (last_expr_to_raise_impossible ~loc original_function_name expr)
          in
          let item = { fn with pexp_attributes = expr.pexp_attributes } in
          make_vb_with_melange_only ~loc ~type_constraint pattern item
      | Pexp_function
          ({ pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _, _, Pfunction_body expr) ->
          let original_function_name = get_function_name pattern.ppat_desc in
          let new_fun_pattern = remove_type_constraint fun_pattern in
          let fn =
            Builder.pexp_fun ~loc arg_label None new_fun_pattern
              (last_expr_to_raise_impossible ~loc original_function_name expr)
          in
          let item = { fn with pexp_attributes = expr.pexp_attributes } in
          make_vb_with_melange_only ~loc pattern item
      | Pexp_function ([], _, Pfunction_cases (_cases, _, _)) ->
          (* Because pexp_function with cases doesn't have a pattern, neither a label, we construct an empty pattern and use it to generate the vb *)
          let original_function_name = get_function_name pattern.ppat_desc in
          let fn =
            Builder.pexp_fun ~loc Nolabel None
              [%pat? _]
              (last_expr_to_raise_impossible ~loc original_function_name expression)
          in
          let item = { fn with pexp_attributes = expression.pexp_attributes } in
          make_vb_with_melange_only ~loc pattern item
      | Pexp_ident { txt = _longident; loc } ->
          let item = [%expr Obj.magic ()] in
          make_vb_with_melange_only ~loc pattern item
      | Pexp_newtype (type_name, expr) ->
          let original_function_name = type_name.txt in
          let item = last_expr_to_raise_impossible ~loc original_function_name expr in
          make_vb_with_melange_only ~loc pattern item
      | _expr -> do_nothing rec_flag
    in

    match !mode with
    (* When it's -js, keep item as it is *)
    | Js -> do_nothing rec_flag
    | Native -> add_melange_only_alert expression

  let structure_item_rule =
    Context_free.Rule.extension
      (Extension.V3.declare melange_only Extension.Context.structure_item extractor_vb structure_item_handler)

  let rules = [ expression_rule; structure_item_rule ]
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

  let expression_error ~loc attrs =
    let name =
      match List.find_opt (fun attr -> eval_attr attr = `drop) attrs with Some attr -> attr.attr_name.txt | None -> ""
    in
    [%expr
      [%ocaml.error
        [%e Builder.estring ~loc (Printf.sprintf "Don't use %s on expressions, use switch%%platform instead" name)]]]

  let rec should_keep attrs =
    match attrs with [] -> `keep | attr :: attrs -> if eval_attr attr = `drop then `drop else should_keep attrs

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
    | Psig_extension _ | Psig_attribute _ -> Some sigi

  let traverse =
    object (_ : Ast_traverse.map)
      inherit Ast_traverse.map as super

      method! structure str =
        let str = super#structure str in
        match str with
        | { pstr_desc = Pstr_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then rest else []
        | str -> List.filter_map apply_config_on_structure_item str

      method! signature sigi =
        let sigi = super#signature sigi in
        match sigi with
        | { psig_desc = Psig_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then rest else []
        | _ -> List.filter_map apply_config_on_signature_item sigi

      method! expression expr =
        let expr = super#expression expr in
        let loc = expr.pexp_loc in
        match expr.pexp_desc with
        | Pexp_let (_, [ { pvb_attributes = attrs; _ } ], _) ->
            let loc = expr.pexp_loc in
            if should_keep attrs = `keep then expr else expression_error ~loc attrs
        | _ -> if should_keep expr.pexp_attributes = `keep then expr else expression_error ~loc expr.pexp_attributes

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
end

let () =
  Driver.add_arg "-js" (Unit (fun () -> mode := Js)) ~doc:"preprocess for js build";
  let rules = Platform.rule :: Melange_only.rules in
  Driver.V2.register_transformation "ppx_platform" ~rules
    ~impl:(fun _ structure -> Preprocess.traverse#structure structure)
    ~intf:(fun _ signature -> Preprocess.traverse#signature signature)
