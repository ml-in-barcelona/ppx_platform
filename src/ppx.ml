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
  let pattern = Ast_pattern.(__')

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

  let prepare_param_pattern ~outer_refs pat =
    let shadowed_values, shadowed_modules = Scope.shadowed_sets outer_refs in
    let pat = remove_type_constraint pat in
    let pat = Scope.wildcard_shadowed_pattern ~shadowed_values ~shadowed_modules pat in
    (pat, Scope.pattern_bindings pat)

  let wrap_with_ignores ~loc ~suppress_alert ~kept_bindings ~outer_refs body =
    let modules_used_by_values =
      Scope.Longident_set.fold
        (fun lid acc ->
          match lid with
          | Ldot (mod_lid, _) -> (
              match Scope.root_module_of_longident mod_lid with
              | Some root -> Scope.String_set.add root acc
              | None -> acc)
          | Lident _ | Lapply _ -> acc)
        outer_refs.Scope.ref_values Scope.String_set.empty
    in
    let outer_modules_only = Scope.String_set.diff outer_refs.ref_modules modules_used_by_values in
    let all_modules = Scope.String_set.union kept_bindings.Scope.bound_modules outer_modules_only in
    let all_values =
      Scope.String_set.fold
        (fun name acc -> Scope.Longident_set.add (Lident name) acc)
        kept_bindings.Scope.bound_values outer_refs.ref_values
    in
    let body =
      List.fold_right
        (fun lid acc ->
          let vb =
            Builder.value_binding ~loc ~pat:(Builder.ppat_any ~loc) ~expr:(Builder.pexp_ident ~loc { txt = lid; loc })
          in
          let vb =
            if suppress_alert && Scope.Longident_set.mem lid outer_refs.ref_melange_only_values then
              { vb with pvb_attributes = [ remove_alert_only ~loc ] }
            else vb
          in
          Builder.pexp_let ~loc Nonrecursive [ vb ] acc)
        (Scope.Longident_set.elements all_values)
        body
    in
    List.fold_right
      (fun mod_name acc ->
        Builder.pexp_letmodule ~loc { txt = None; loc } (Builder.pmod_ident ~loc { txt = Lident mod_name; loc }) acc)
      (Scope.String_set.elements all_modules) body

  let rec last_expr_to_raise_melange_only ~loc ~suppress_alert ~outer_refs ~kept_bindings original_name expr =
    match expr.pexp_desc with
    | Pexp_constraint (expr, _) ->
        last_expr_to_raise_melange_only ~loc ~suppress_alert ~outer_refs ~kept_bindings original_name expr
    | Pexp_function
        ( { pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _rest,
          _,
          Pfunction_body expression ) ->
        let new_fun_pattern, param_bindings = prepare_param_pattern ~outer_refs fun_pattern in
        let kept_bindings = Scope.merge_bindings kept_bindings param_bindings in
        let fn =
          Builder.pexp_fun ~loc arg_label None new_fun_pattern
            (last_expr_to_raise_melange_only ~loc ~suppress_alert ~outer_refs ~kept_bindings original_name expression)
        in
        { fn with pexp_attributes = expr.pexp_attributes }
    | _ ->
        wrap_with_ignores ~loc ~suppress_alert ~kept_bindings ~outer_refs
          [%expr Ppx_platform.fail_melange_only [%e Builder.estring ~loc original_name]]

  let melange_only_fun ~loc ~outer_refs arg_label pattern expression =
    let stringified = Ppxlib.Pprintast.string_of_expression expression in
    let message = Builder.estring ~loc stringified in
    let new_pattern, kept_bindings = prepare_param_pattern ~outer_refs pattern in
    let body =
      wrap_with_ignores ~loc ~suppress_alert:true ~kept_bindings ~outer_refs
        [%expr Ppx_platform.fail_melange_only [%e message]]
    in
    let fn = Builder.pexp_fun ~loc arg_label None new_pattern body in
    { fn with pexp_attributes = expression.pexp_attributes }

  let melange_only_value_binding ~scope pattern expression =
    let loc = pattern.ppat_loc in
    match pattern with
    | [%pat? ()] ->
        let outer_refs = Scope.collect_free_in_expr ~outer:scope expression in
        let expr =
          wrap_with_ignores ~loc ~suppress_alert:true ~kept_bindings:Scope.empty_bindings ~outer_refs [%expr ()]
        in
        Builder.value_binding ~loc ~pat:pattern ~expr
    | _ -> (
        match expression.pexp_desc with
        | Pexp_constraint
            ({ pexp_desc = Pexp_function ({ pparam_desc = Pparam_val _; _ } :: _, _, Pfunction_body _); _ }, _)
        | Pexp_function ({ pparam_desc = Pparam_val _; _ } :: _, _, Pfunction_body _) ->
            let function_name = get_function_name pattern.ppat_desc in
            let outer_refs = Scope.collect_free_in_expr ~outer:scope expression in
            let expr =
              last_expr_to_raise_melange_only ~loc ~suppress_alert:false ~outer_refs ~kept_bindings:Scope.empty_bindings
                function_name expression
            in
            let vb = Builder.value_binding ~loc ~pat:pattern ~expr in
            { vb with pvb_attributes = [ remove_alert_only ~loc ] }
        | _ -> Builder.value_binding ~loc ~pat:pattern ~expr:(error_only_works_on ~loc))

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
    let warning =
      Builder.attribute ~loc ~name:{ txt = "warning"; loc }
        ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc "-32") [] ])
    in
    let vb = Builder.value_binding ~loc ~pat:pattern ~expr:expression in
    { vb with pvb_attributes = [ warning ] }

  let rewrite_structure_vb ~loc ~scope vb =
    let pattern = vb.pvb_pat in
    let expression = vb.pvb_expr in
    let outer_refs = Scope.collect_free_in_expr ~outer:scope expression in
    match expression.pexp_desc with
    | Pexp_constraint
        ( {
            pexp_desc =
              Pexp_function
                ({ pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _, _, Pfunction_body expr);
            _;
          },
          type_constraint ) ->
        let original_function_name = get_function_name pattern.ppat_desc in
        let new_fun_pattern, kept_bindings = prepare_param_pattern ~outer_refs fun_pattern in
        let fn =
          Builder.pexp_fun ~loc arg_label None new_fun_pattern
            (last_expr_to_raise_melange_only ~loc ~suppress_alert:false ~outer_refs ~kept_bindings
               original_function_name expr)
        in
        let item = { fn with pexp_attributes = expr.pexp_attributes } in
        (`Rewritten, make_vb_with_melange_only ~loc ~type_constraint pattern item)
    | Pexp_function
        ({ pparam_desc = Pparam_val (arg_label, _arg_expression, fun_pattern); _ } :: _, _, Pfunction_body expr) ->
        let original_function_name = get_function_name pattern.ppat_desc in
        let new_fun_pattern, kept_bindings = prepare_param_pattern ~outer_refs fun_pattern in
        let fn =
          Builder.pexp_fun ~loc arg_label None new_fun_pattern
            (last_expr_to_raise_melange_only ~loc ~suppress_alert:false ~outer_refs ~kept_bindings
               original_function_name expr)
        in
        let item = { fn with pexp_attributes = expr.pexp_attributes } in
        (`Rewritten, make_vb_with_melange_only ~loc pattern item)
    | Pexp_function ([], _, Pfunction_cases (_cases, _, _)) ->
        let original_function_name = get_function_name pattern.ppat_desc in
        let fn =
          Builder.pexp_fun ~loc Nolabel None
            [%pat? _]
            (last_expr_to_raise_melange_only ~loc ~suppress_alert:false ~outer_refs ~kept_bindings:Scope.empty_bindings
               original_function_name expression)
        in
        let item = { fn with pexp_attributes = expression.pexp_attributes } in
        (`Rewritten, make_vb_with_melange_only ~loc pattern item)
    | Pexp_ident { txt = _; loc } ->
        let item =
          wrap_with_ignores ~loc ~suppress_alert:false ~kept_bindings:Scope.empty_bindings ~outer_refs
            [%expr Obj.magic ()]
        in
        (`Rewritten, make_vb_with_melange_only ~loc pattern item)
    | Pexp_newtype (type_name, expr) ->
        let original_function_name = type_name.txt in
        let item =
          last_expr_to_raise_melange_only ~loc ~suppress_alert:false ~outer_refs ~kept_bindings:Scope.empty_bindings
            original_function_name expr
        in
        (`Rewritten, make_vb_with_melange_only ~loc pattern item)
    | _ -> (`Unchanged, vb)

  let mapper =
    object (self)
      inherit [Scope.t] Ast_traverse.map_with_context as super

      method private eval_structure outer items =
        let rev_items, _, exported =
          List.fold_left
            (fun (acc, ambient, exported) item ->
              match item.pstr_desc with
              | Pstr_value (Nonrecursive, vbs) ->
                  let vbs' = List.map (self#value_binding ambient) vbs in
                  let ambient' = Scope.add_value_bindings vbs ambient in
                  let exported' = Scope.add_value_bindings vbs exported in
                  ({ item with pstr_desc = Pstr_value (Nonrecursive, vbs') } :: acc, ambient', exported')
              | Pstr_value (Recursive, vbs) ->
                  let ambient' = Scope.add_value_bindings vbs ambient in
                  let exported' = Scope.add_value_bindings vbs exported in
                  let vbs' = List.map (self#value_binding ambient') vbs in
                  ({ item with pstr_desc = Pstr_value (Recursive, vbs') } :: acc, ambient', exported')
              | Pstr_primitive vd ->
                  let vd' = self#value_description ambient vd in
                  let ambient' = Scope.add_value vd.pval_name.txt ambient in
                  let exported' = Scope.add_value vd.pval_name.txt exported in
                  ({ item with pstr_desc = Pstr_primitive vd' } :: acc, ambient', exported')
              | Pstr_module mb ->
                  let expr', mod_info = self#eval_module_expr ambient mb.pmb_expr in
                  let mb' = { mb with pmb_expr = expr' } in
                  let ambient', exported' =
                    match mb.pmb_name.txt with
                    | Some name -> (Scope.add_module name mod_info ambient, Scope.add_module name mod_info exported)
                    | None -> (ambient, exported)
                  in
                  ({ item with pstr_desc = Pstr_module mb' } :: acc, ambient', exported')
              | Pstr_recmodule mbs ->
                  let add_rec_mods scope =
                    List.fold_left
                      (fun s mb ->
                        match mb.pmb_name.txt with Some name -> Scope.add_module name Scope.Opaque s | None -> s)
                      scope mbs
                  in
                  let ambient' = add_rec_mods ambient in
                  let exported' = add_rec_mods exported in
                  let mbs' = List.map (self#module_binding ambient') mbs in
                  ({ item with pstr_desc = Pstr_recmodule mbs' } :: acc, ambient', exported')
              | Pstr_include inc ->
                  let mod', mod_info = self#eval_module_expr ambient inc.pincl_mod in
                  let ambient', exported' =
                    match mod_info with
                    | Scope.Struct sub -> (Scope.merge ambient sub, Scope.merge exported sub)
                    | Scope.Opaque -> (ambient, exported)
                  in
                  ({ item with pstr_desc = Pstr_include { inc with pincl_mod = mod' } } :: acc, ambient', exported')
              | Pstr_open od ->
                  let mod', mod_info = self#eval_module_expr ambient od.popen_expr in
                  let ambient' =
                    match mod_info with Scope.Struct sub -> Scope.merge ambient sub | Scope.Opaque -> ambient
                  in
                  ({ item with pstr_desc = Pstr_open { od with popen_expr = mod' } } :: acc, ambient', exported)
              | Pstr_extension (({ txt; _ }, PStr [ { pstr_desc = Pstr_value (rec_flag, vbs); _ } ]), _)
                when String.equal txt melange_only -> (
                  let loc = item.pstr_loc in
                  match !mode with
                  | Js -> (
                      match rec_flag with
                      | Recursive ->
                          let ambient' = Scope.add_value_bindings vbs ambient in
                          let exported' = Scope.add_value_bindings vbs exported in
                          let vbs' = List.map (self#value_binding ambient') vbs in
                          (Builder.pstr_value ~loc Recursive vbs' :: acc, ambient', exported')
                      | Nonrecursive ->
                          let vbs' = List.map (self#value_binding ambient) vbs in
                          let ambient' = Scope.add_value_bindings vbs ambient in
                          let exported' = Scope.add_value_bindings vbs exported in
                          (Builder.pstr_value ~loc Nonrecursive vbs' :: acc, ambient', exported'))
                  | Native ->
                      let vb_scope =
                        match rec_flag with
                        | Recursive -> Scope.add_value_bindings ~melange_only:true vbs ambient
                        | Nonrecursive -> ambient
                      in
                      let results =
                        List.map
                          (fun vb ->
                            match rewrite_structure_vb ~loc ~scope:vb_scope vb with
                            | `Rewritten, vb' -> (true, vb')
                            | `Unchanged, vb -> (false, self#value_binding vb_scope vb))
                          vbs
                      in
                      let vbs' = List.map snd results in
                      let ambient', exported' =
                        List.fold_left
                          (fun (amb, exp) (is_mel, vb) ->
                            ( Scope.add_pattern ~melange_only:is_mel vb.pvb_pat amb,
                              Scope.add_pattern ~melange_only:is_mel vb.pvb_pat exp ))
                          (ambient, exported)
                          (List.map2 (fun (is_mel, _) vb -> (is_mel, vb)) results vbs)
                      in
                      (Builder.pstr_value ~loc rec_flag vbs' :: acc, ambient', exported'))
              | _ ->
                  let item' = self#structure_item ambient item in
                  (item' :: acc, ambient, exported))
            ([], outer, Scope.empty) items
        in
        (List.rev rev_items, exported)

      method private eval_module_expr scope me =
        match me.pmod_desc with
        | Pmod_structure items ->
            let items', exported = self#eval_structure scope items in
            ({ me with pmod_desc = Pmod_structure items' }, Scope.Struct exported)
        | Pmod_ident { txt = lid; _ } ->
            let info = match Scope.resolve_module scope lid with Some info -> info | None -> Scope.Opaque in
            (me, info)
        | Pmod_constraint (inner, mty) ->
            let inner' = self#module_expr scope inner in
            let mty' = self#module_type scope mty in
            ({ me with pmod_desc = Pmod_constraint (inner', mty') }, Scope.of_module_type mty')
        | Pmod_functor (Named (({ txt = Some name; _ } as name_loc), mty), body) ->
            let mty' = self#module_type scope mty in
            let body' = self#module_expr (Scope.add_module name (Scope.of_module_type mty') scope) body in
            ({ me with pmod_desc = Pmod_functor (Named (name_loc, mty'), body') }, Scope.Opaque)
        | _ -> (super#module_expr scope me, Scope.Opaque)

      method! structure scope items = fst (self#eval_structure scope items)
      method! module_expr scope me = fst (self#eval_module_expr scope me)

      method! expression scope expr =
        match expr.pexp_desc with
        | Pexp_extension ({ txt; _ }, PStr [ { pstr_desc = Pstr_eval (payload, []); _ } ])
          when String.equal txt melange_only -> (
            let loc = expr.pexp_loc in
            match !mode with
            | Js -> self#expression scope payload
            | Native -> (
                match payload.pexp_desc with
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
                    let outer_refs = Scope.collect_free_in_expr ~outer:scope payload in
                    let fn = melange_only_fun ~loc ~outer_refs arg_label pattern expression in
                    Builder.pexp_constraint ~loc
                      { fn with pexp_attributes = expression.pexp_attributes }
                      type_constraint
                | Pexp_function
                    ({ pparam_desc = Pparam_val (arg_label, _arg_expression, pattern); _ } :: _, _, Pfunction_body inner)
                  ->
                    let outer_refs = Scope.collect_free_in_expr ~outer:scope payload in
                    let function_name = get_function_name pattern.ppat_desc in
                    let new_fun_pattern, kept_bindings = prepare_param_pattern ~outer_refs pattern in
                    Builder.pexp_fun ~loc arg_label None new_fun_pattern
                      (last_expr_to_raise_melange_only ~loc ~suppress_alert:true ~outer_refs ~kept_bindings
                         function_name inner)
                | Pexp_let (rec_flag, value_bindings, body) ->
                    let vb_scope =
                      match rec_flag with
                      | Recursive -> Scope.add_value_bindings value_bindings scope
                      | Nonrecursive -> scope
                    in
                    let vbs' =
                      List.map
                        (fun binding -> melange_only_value_binding ~scope:vb_scope binding.pvb_pat binding.pvb_expr)
                        value_bindings
                    in
                    let body' = self#expression (Scope.add_value_bindings value_bindings scope) body in
                    Builder.pexp_let ~loc rec_flag vbs' body'
                | _ -> error_only_works_on ~loc))
        | Pexp_let (Nonrecursive, vbs, body) ->
            let vbs' = List.map (self#value_binding scope) vbs in
            let body' = self#expression (Scope.add_value_bindings vbs scope) body in
            { expr with pexp_desc = Pexp_let (Nonrecursive, vbs', body') }
        | Pexp_let (Recursive, vbs, body) ->
            let scope' = Scope.add_value_bindings vbs scope in
            let vbs' = List.map (self#value_binding scope') vbs in
            let body' = self#expression scope' body in
            { expr with pexp_desc = Pexp_let (Recursive, vbs', body') }
        | Pexp_letop { let_; ands; body } ->
            let map_bop bop = { bop with pbop_exp = self#expression scope bop.pbop_exp } in
            let let_' = map_bop let_ in
            let ands' = List.map map_bop ands in
            let scope' = List.fold_left (fun s bop -> Scope.add_pattern bop.pbop_pat s) scope (let_ :: ands) in
            let body' = self#expression scope' body in
            { expr with pexp_desc = Pexp_letop { let_ = let_'; ands = ands'; body = body' } }
        | Pexp_function (params, constraint_, body) ->
            let rev_params, scope' =
              List.fold_left
                (fun (acc, s) param ->
                  match param.pparam_desc with
                  | Pparam_val (lbl, default_opt, pat) ->
                      let default_opt' = Option.map (self#expression s) default_opt in
                      let s' = Scope.add_pattern pat s in
                      ({ param with pparam_desc = Pparam_val (lbl, default_opt', pat) } :: acc, s')
                  | Pparam_newtype _ -> (param :: acc, s))
                ([], scope) params
            in
            let body' =
              match body with
              | Pfunction_body e -> Pfunction_body (self#expression scope' e)
              | Pfunction_cases (cases, loc, attrs) -> Pfunction_cases (self#cases scope' cases, loc, attrs)
            in
            { expr with pexp_desc = Pexp_function (List.rev rev_params, constraint_, body') }
        | Pexp_for (pat, e1, e2, dir, body) ->
            let e1' = self#expression scope e1 in
            let e2' = self#expression scope e2 in
            let body' = self#expression (Scope.add_pattern pat scope) body in
            { expr with pexp_desc = Pexp_for (pat, e1', e2', dir, body') }
        | Pexp_letmodule (name_opt, mod_expr, body) ->
            let mod_expr', mod_info = self#eval_module_expr scope mod_expr in
            let scope' = match name_opt.txt with Some name -> Scope.add_module name mod_info scope | None -> scope in
            let body' = self#expression scope' body in
            { expr with pexp_desc = Pexp_letmodule (name_opt, mod_expr', body') }
        | Pexp_open (od, body) ->
            let mod_expr', mod_info = self#eval_module_expr scope od.popen_expr in
            let scope' = match mod_info with Scope.Struct sub -> Scope.merge scope sub | Scope.Opaque -> scope in
            let body' = self#expression scope' body in
            { expr with pexp_desc = Pexp_open ({ od with popen_expr = mod_expr' }, body') }
        | Pexp_object cls_str ->
            let scope' = Scope.add_pattern cls_str.pcstr_self scope in
            let scope' =
              List.fold_left
                (fun s field -> match field.pcf_desc with Pcf_val (name, _, _) -> Scope.add_value name.txt s | _ -> s)
                scope' cls_str.pcstr_fields
            in
            let fields' = List.map (self#class_field scope') cls_str.pcstr_fields in
            { expr with pexp_desc = Pexp_object { cls_str with pcstr_fields = fields' } }
        | _ -> super#expression scope expr

      method! case scope case =
        let scope' = Scope.add_pattern case.pc_lhs scope in
        {
          case with
          pc_guard = Option.map (self#expression scope') case.pc_guard;
          pc_rhs = self#expression scope' case.pc_rhs;
        }

      method! class_expr scope ce =
        match ce.pcl_desc with
        | Pcl_fun (lbl, default_opt, pat, body) ->
            let default_opt' = Option.map (self#expression scope) default_opt in
            let body' = self#class_expr (Scope.add_pattern pat scope) body in
            { ce with pcl_desc = Pcl_fun (lbl, default_opt', pat, body') }
        | Pcl_let (Nonrecursive, vbs, body) ->
            let vbs' = List.map (self#value_binding scope) vbs in
            let body' = self#class_expr (Scope.add_value_bindings vbs scope) body in
            { ce with pcl_desc = Pcl_let (Nonrecursive, vbs', body') }
        | Pcl_let (Recursive, vbs, body) ->
            let scope' = Scope.add_value_bindings vbs scope in
            let vbs' = List.map (self#value_binding scope') vbs in
            let body' = self#class_expr scope' body in
            { ce with pcl_desc = Pcl_let (Recursive, vbs', body') }
        | _ -> super#class_expr scope ce
    end

  let traverse structure = mapper#structure Scope.empty structure
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
    object (self : Ast_traverse.map)
      inherit Ast_traverse.map as super

      method! structure str =
        let str = super#structure str in
        match str with
        | { pstr_desc = Pstr_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then rest else []
        | str -> List.filter_map apply_config_on_structure_item str

      method! structure_item stri =
        match (!mode, stri.pstr_desc) with
        | Native, Pstr_extension (({ txt; _ }, _), _) when String.equal txt melange_only -> stri
        | _ -> super#structure_item stri

      method! signature sigi =
        let sigi = super#signature sigi in
        match sigi with
        | { psig_desc = Psig_attribute attr; _ } :: rest when is_platform_tag attr.attr_name.txt ->
            if eval_attr attr = `keep then rest else []
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
        | _ -> (
            let expr = super#expression expr in
            let loc = expr.pexp_loc in
            match expr.pexp_desc with
            | Pexp_let (_, [ { pvb_attributes = attrs; _ } ], _) ->
                let loc = expr.pexp_loc in
                if should_keep attrs = `keep then expr else expression_error ~loc attrs
            | _ -> if should_keep expr.pexp_attributes = `keep then expr else expression_error ~loc expr.pexp_attributes
            )

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
  let rules = Platform.rule :: Removed.rules in
  Driver.V2.register_transformation "ppx_platform" ~rules
    ~impl:(fun _ structure ->
      Removed.reject#structure structure;
      let structure = Preprocess.traverse#structure structure in
      Melange_only.traverse structure)
    ~intf:(fun _ signature ->
      Removed.reject#signature signature;
      Preprocess.traverse#signature signature)
