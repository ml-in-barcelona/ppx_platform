open Ppxlib
module String_set = Set.Make (String)
module String_map = Map.Make (String)

module Longident_set = Set.Make (struct
  type t = Longident.t

  let rec compare a b =
    match (a, b) with
    | Lident a, Lident b -> String.compare a b
    | Ldot (a1, a2), Ldot (b1, b2) ->
        let c = compare a1 b1 in
        if c <> 0 then c else String.compare a2 b2
    | Lapply (a1, a2), Lapply (b1, b2) ->
        let c = compare a1 b1 in
        if c <> 0 then c else compare a2 b2
    | Lident _, (Ldot _ | Lapply _) -> -1
    | Ldot _, Lident _ -> 1
    | Ldot _, Lapply _ -> -1
    | Lapply _, (Lident _ | Ldot _) -> 1
end)

type module_info = Opaque | Struct of t
and t = { values : String_set.t; melange_only_values : String_set.t; modules : module_info String_map.t }

type bindings = { bound_values : String_set.t; bound_modules : String_set.t }
type refs = { ref_values : Longident_set.t; ref_melange_only_values : Longident_set.t; ref_modules : String_set.t }

let empty = { values = String_set.empty; melange_only_values = String_set.empty; modules = String_map.empty }
let empty_bindings = { bound_values = String_set.empty; bound_modules = String_set.empty }

let empty_refs =
  { ref_values = Longident_set.empty; ref_melange_only_values = Longident_set.empty; ref_modules = String_set.empty }

let merge_bindings a b =
  {
    bound_values = String_set.union a.bound_values b.bound_values;
    bound_modules = String_set.union a.bound_modules b.bound_modules;
  }

let merge outer inner =
  {
    values = String_set.union outer.values inner.values;
    melange_only_values =
      String_set.union (String_set.diff outer.melange_only_values inner.values) inner.melange_only_values;
    modules = String_map.union (fun _ _ right -> Some right) outer.modules inner.modules;
  }

let add_value ?(melange_only = false) name scope =
  let melange_only_values =
    if melange_only then String_set.add name scope.melange_only_values
    else String_set.remove name scope.melange_only_values
  in
  { scope with values = String_set.add name scope.values; melange_only_values }

let add_module name info scope = { scope with modules = String_map.add name info scope.modules }

let rec of_signature items =
  List.fold_left
    (fun acc item ->
      match item.psig_desc with
      | Psig_value vd -> add_value vd.pval_name.txt acc
      | Psig_module { pmd_name = { txt = Some name; _ }; pmd_type; _ } -> add_module name (of_module_type pmd_type) acc
      | Psig_recmodule mds ->
          List.fold_left
            (fun s md -> match md.pmd_name.txt with Some name -> add_module name Opaque s | None -> s)
            acc mds
      | Psig_include { pincl_mod; _ } -> (
          match of_module_type pincl_mod with Struct sub -> merge acc sub | Opaque -> acc)
      | _ -> acc)
    empty items

and of_module_type mty = match mty.pmty_desc with Pmty_signature items -> Struct (of_signature items) | _ -> Opaque

let rec collect_pattern_bindings acc pat =
  match pat.ppat_desc with
  | Ppat_var { txt; _ } -> { acc with bound_values = String_set.add txt acc.bound_values }
  | Ppat_alias (p, { txt; _ }) ->
      collect_pattern_bindings { acc with bound_values = String_set.add txt acc.bound_values } p
  | Ppat_unpack { txt = Some name; _ } -> { acc with bound_modules = String_set.add name acc.bound_modules }
  | Ppat_tuple pats | Ppat_array pats -> List.fold_left collect_pattern_bindings acc pats
  | Ppat_construct (_, Some (_, p))
  | Ppat_variant (_, Some p)
  | Ppat_constraint (p, _)
  | Ppat_lazy p
  | Ppat_exception p
  | Ppat_open (_, p) ->
      collect_pattern_bindings acc p
  | Ppat_record (fields, _) -> List.fold_left (fun acc (_, p) -> collect_pattern_bindings acc p) acc fields
  | Ppat_or (p1, _) -> collect_pattern_bindings acc p1
  | Ppat_any | Ppat_constant _ | Ppat_interval _
  | Ppat_construct (_, None)
  | Ppat_variant (_, None)
  | Ppat_type _
  | Ppat_unpack { txt = None; _ }
  | Ppat_extension _ ->
      acc

let pattern_bindings pat = collect_pattern_bindings empty_bindings pat

let add_bindings ?(melange_only = false) bindings scope =
  let scope = String_set.fold (fun name acc -> add_value ~melange_only name acc) bindings.bound_values scope in
  String_set.fold (fun name acc -> add_module name Opaque acc) bindings.bound_modules scope

let add_pattern ?(melange_only = false) pat scope = add_bindings ~melange_only (pattern_bindings pat) scope

let add_value_bindings ?(melange_only = false) vbs scope =
  List.fold_left (fun acc vb -> add_pattern ~melange_only vb.pvb_pat acc) scope vbs

let rec root_module_of_longident = function
  | Lident name -> Some name
  | Ldot (parent, _) -> root_module_of_longident parent
  | Lapply (fn, _) -> root_module_of_longident fn

let rec resolve_module scope = function
  | Lident name -> String_map.find_opt name scope.modules
  | Ldot (parent, name) -> (
      match resolve_module scope parent with
      | Some (Struct sub) -> String_map.find_opt name sub.modules
      | Some Opaque | None -> None)
  | Lapply _ -> None

let resolve_value scope = function
  | Lident name ->
      if String_set.mem name scope.values then `Value (Lident name, String_set.mem name scope.melange_only_values)
      else `Not_found
  | Ldot (mod_lid, name) as full_lid -> (
      match resolve_module scope mod_lid with
      | Some (Struct sub) when String_set.mem name sub.values ->
          `Value (full_lid, String_set.mem name sub.melange_only_values)
      | _ -> (
          match root_module_of_longident mod_lid with
          | Some root when String_map.mem root scope.modules -> `Module root
          | _ -> `Not_found))
  | Lapply _ -> `Not_found

let add_ref_value ~melange_only lid refs =
  let ref_melange_only_values =
    if melange_only then Longident_set.add lid refs.ref_melange_only_values else refs.ref_melange_only_values
  in
  { refs with ref_values = Longident_set.add lid refs.ref_values; ref_melange_only_values }

let add_ref_module name refs = { refs with ref_modules = String_set.add name refs.ref_modules }

type locals = { local_values : String_set.t; local_modules : String_set.t; local_opens : (Longident.t * t) list }

let empty_locals = { local_values = String_set.empty; local_modules = String_set.empty; local_opens = [] }

let add_local_bindings bindings locals =
  {
    locals with
    local_values = String_set.union locals.local_values bindings.bound_values;
    local_modules = String_set.union locals.local_modules bindings.bound_modules;
  }

let rec qualify_longident prefix = function
  | Lident name -> Ldot (prefix, name)
  | Ldot (parent, name) -> Ldot (qualify_longident prefix parent, name)
  | Lapply (a, b) -> Lapply (qualify_longident prefix a, b)

let rec find_in_opens_value name = function
  | [] -> None
  | (prefix, sub) :: rest ->
      if String_set.mem name sub.values then Some (Ldot (prefix, name), String_set.mem name sub.melange_only_values)
      else find_in_opens_value name rest

let rec find_in_opens_dot mod_lid name = function
  | [] -> None
  | (prefix, sub) :: rest -> (
      match resolve_module sub mod_lid with
      | Some (Struct nested) when String_set.mem name nested.values ->
          Some (`Value (Ldot (qualify_longident prefix mod_lid, name), String_set.mem name nested.melange_only_values))
      | _ -> (
          match root_module_of_longident mod_lid with
          | Some root when String_map.mem root sub.modules -> (
              match root_module_of_longident prefix with Some root_prefix -> Some (`Module root_prefix) | None -> None)
          | _ -> find_in_opens_dot mod_lid name rest))

let record_value_ident ~outer locals refs lid =
  match lid with
  | Lident name -> (
      if String_set.mem name locals.local_values then refs
      else
        match find_in_opens_value name locals.local_opens with
        | Some (qualified, melange_only) -> add_ref_value ~melange_only qualified refs
        | None -> (
            match resolve_value outer lid with
            | `Value (v_lid, melange_only) -> add_ref_value ~melange_only v_lid refs
            | `Module m -> add_ref_module m refs
            | `Not_found -> refs))
  | Ldot (mod_lid, name) -> (
      match root_module_of_longident mod_lid with
      | Some root when String_set.mem root locals.local_modules -> refs
      | _ -> (
          match find_in_opens_dot mod_lid name locals.local_opens with
          | Some (`Value (v_lid, melange_only)) -> add_ref_value ~melange_only v_lid refs
          | Some (`Module m) -> add_ref_module m refs
          | None -> (
              match resolve_value outer lid with
              | `Value (v_lid, melange_only) -> add_ref_value ~melange_only v_lid refs
              | `Module m -> add_ref_module m refs
              | `Not_found -> refs)))
  | Lapply _ -> refs

let rec record_module_ident ~outer locals refs = function
  | Lapply (a, b) ->
      let refs = record_module_ident ~outer locals refs a in
      record_module_ident ~outer locals refs b
  | (Lident _ | Ldot _) as lid -> (
      match root_module_of_longident lid with
      | Some root when String_set.mem root locals.local_modules -> refs
      | Some root when String_map.mem root outer.modules -> add_ref_module root refs
      | _ -> refs)

let rec local_bindings_of_structure_item item =
  match item.pstr_desc with
  | Pstr_value (_, vbs) ->
      List.fold_left (fun acc vb -> merge_bindings acc (pattern_bindings vb.pvb_pat)) empty_bindings vbs
  | Pstr_primitive vd -> { empty_bindings with bound_values = String_set.singleton vd.pval_name.txt }
  | Pstr_module { pmb_name = { txt = Some name; _ }; _ } ->
      { empty_bindings with bound_modules = String_set.singleton name }
  | Pstr_recmodule mbs ->
      List.fold_left
        (fun acc mb ->
          match mb.pmb_name.txt with
          | Some name -> { acc with bound_modules = String_set.add name acc.bound_modules }
          | None -> acc)
        empty_bindings mbs
  | Pstr_include { pincl_mod = { pmod_desc = Pmod_structure items; _ }; _ } ->
      List.fold_left (fun acc i -> merge_bindings acc (local_bindings_of_structure_item i)) empty_bindings items
  | _ -> empty_bindings

let collect_free_in_expr ~outer expr =
  let collector =
    object (self)
      inherit [locals * refs] Ast_traverse.fold as super

      method private with_locals :
          'a. locals -> ('a -> locals * refs -> locals * refs) -> 'a -> locals * refs -> locals * refs =
        fun locals' fn x (saved_locals, refs) ->
          let _, refs = fn x (locals', refs) in
          (saved_locals, refs)

      method private record_mod_lid lid (locals, refs) = (locals, record_module_ident ~outer locals refs lid)

      method! expression expr ((locals, refs) as acc) =
        match expr.pexp_desc with
        | Pexp_ident { txt; _ } -> (locals, record_value_ident ~outer locals refs txt)
        | Pexp_construct ({ txt = Ldot (mod_lid, _); _ }, arg) ->
            let acc = self#record_mod_lid mod_lid acc in
            Option.fold ~none:acc ~some:(fun e -> self#expression e acc) arg
        | Pexp_field (e, { txt = Ldot (mod_lid, _); _ }) ->
            let acc = self#record_mod_lid mod_lid acc in
            self#expression e acc
        | Pexp_setfield (e1, { txt = Ldot (mod_lid, _); _ }, e2) ->
            let acc = self#record_mod_lid mod_lid acc in
            let acc = self#expression e1 acc in
            self#expression e2 acc
        | Pexp_record (fields, with_e) ->
            let acc =
              List.fold_left
                (fun acc ({ txt; _ }, field_expr) ->
                  let acc =
                    match txt with Ldot (mod_lid, _) -> self#record_mod_lid mod_lid acc | Lident _ | Lapply _ -> acc
                  in
                  self#expression field_expr acc)
                acc fields
            in
            Option.fold ~none:acc ~some:(fun e -> self#expression e acc) with_e
        | Pexp_let (Nonrecursive, vbs, body) ->
            let acc = List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs in
            let bindings =
              List.fold_left (fun b vb -> merge_bindings b (pattern_bindings vb.pvb_pat)) empty_bindings vbs
            in
            self#with_locals (add_local_bindings bindings locals) self#expression body acc
        | Pexp_let (Recursive, vbs, body) ->
            let bindings =
              List.fold_left (fun b vb -> merge_bindings b (pattern_bindings vb.pvb_pat)) empty_bindings vbs
            in
            let locals' = add_local_bindings bindings locals in
            let acc =
              self#with_locals locals'
                (fun vbs acc -> List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs)
                vbs acc
            in
            self#with_locals locals' self#expression body acc
        | Pexp_letop { let_; ands; body } ->
            let ops = let_ :: ands in
            let acc =
              List.fold_left
                (fun (locals, refs) bop ->
                  let refs = record_value_ident ~outer locals refs (Lident bop.pbop_op.txt) in
                  let acc = self#pattern bop.pbop_pat (locals, refs) in
                  self#expression bop.pbop_exp acc)
                acc ops
            in
            let bindings =
              List.fold_left (fun b bop -> merge_bindings b (pattern_bindings bop.pbop_pat)) empty_bindings ops
            in
            self#with_locals (add_local_bindings bindings locals) self#expression body acc
        | Pexp_function (params, constraint_, body) ->
            let locals', refs =
              List.fold_left
                (fun (locals, refs) param ->
                  match param.pparam_desc with
                  | Pparam_val (_, default_opt, pat) ->
                      let _, refs =
                        Option.fold ~none:(locals, refs) ~some:(fun e -> self#expression e (locals, refs)) default_opt
                      in
                      let _, refs = self#pattern pat (locals, refs) in
                      (add_local_bindings (pattern_bindings pat) locals, refs)
                  | Pparam_newtype _ -> (locals, refs))
                (locals, refs) params
            in
            let acc =
              self#with_locals locals'
                (fun () acc ->
                  let acc =
                    match constraint_ with
                    | Some (Pconstraint ty) -> self#core_type ty acc
                    | Some (Pcoerce (ty_opt, ty)) ->
                        let acc = Option.fold ~none:acc ~some:(fun t -> self#core_type t acc) ty_opt in
                        self#core_type ty acc
                    | None -> acc
                  in
                  match body with
                  | Pfunction_body e -> self#expression e acc
                  | Pfunction_cases (cases, _, _) -> self#cases cases acc)
                () (locals, refs)
            in
            acc
        | Pexp_match (e, cases) | Pexp_try (e, cases) ->
            let acc = self#expression e acc in
            self#cases cases acc
        | Pexp_for (pat, e1, e2, _, body) ->
            let acc = self#pattern pat acc in
            let acc = self#expression e1 acc in
            let acc = self#expression e2 acc in
            self#with_locals (add_local_bindings (pattern_bindings pat) locals) self#expression body acc
        | Pexp_letmodule (name_opt, mod_expr, body) ->
            let acc = self#module_expr mod_expr acc in
            let locals' =
              match name_opt.txt with
              | Some name -> { locals with local_modules = String_set.add name locals.local_modules }
              | None -> locals
            in
            self#with_locals locals' self#expression body acc
        | Pexp_open (od, body) ->
            let acc = self#module_expr od.popen_expr acc in
            let locals' =
              match od.popen_expr.pmod_desc with
              | Pmod_ident { txt = lid; _ } -> (
                  match root_module_of_longident lid with
                  | Some root when String_set.mem root locals.local_modules -> locals
                  | _ -> (
                      match resolve_module outer lid with
                      | Some (Struct sub) ->
                          {
                            local_values = String_set.diff locals.local_values sub.values;
                            local_modules =
                              String_map.fold (fun k _ acc -> String_set.remove k acc) sub.modules locals.local_modules;
                            local_opens = (lid, sub) :: locals.local_opens;
                          }
                      | Some Opaque | None -> locals))
              | Pmod_structure items ->
                  let bindings =
                    List.fold_left
                      (fun b item -> merge_bindings b (local_bindings_of_structure_item item))
                      empty_bindings items
                  in
                  add_local_bindings bindings locals
              | _ -> locals
            in
            self#with_locals locals' self#expression body acc
        | Pexp_object cls_str ->
            let acc = self#pattern cls_str.pcstr_self acc in
            let self_bindings = pattern_bindings cls_str.pcstr_self in
            let val_bindings =
              List.fold_left
                (fun acc field ->
                  match field.pcf_desc with
                  | Pcf_val (name, _, _) -> { acc with bound_values = String_set.add name.txt acc.bound_values }
                  | _ -> acc)
                self_bindings cls_str.pcstr_fields
            in
            self#with_locals
              (add_local_bindings val_bindings locals)
              (fun fields acc -> List.fold_left (fun acc f -> self#class_field f acc) acc fields)
              cls_str.pcstr_fields acc
        | _ -> super#expression expr acc

      method! case case ((locals, _) as acc) =
        let acc = self#pattern case.pc_lhs acc in
        let locals' = add_local_bindings (pattern_bindings case.pc_lhs) locals in
        self#with_locals locals'
          (fun () acc ->
            let acc = Option.fold ~none:acc ~some:(fun g -> self#expression g acc) case.pc_guard in
            self#expression case.pc_rhs acc)
          () acc

      method! pattern pat acc =
        match pat.ppat_desc with
        | Ppat_construct ({ txt = Ldot (mod_lid, _); _ }, arg) ->
            let acc = self#record_mod_lid mod_lid acc in
            Option.fold ~none:acc ~some:(fun (_, p) -> self#pattern p acc) arg
        | Ppat_record (fields, _) ->
            List.fold_left
              (fun acc ({ txt; _ }, p) ->
                let acc =
                  match txt with Ldot (mod_lid, _) -> self#record_mod_lid mod_lid acc | Lident _ | Lapply _ -> acc
                in
                self#pattern p acc)
              acc fields
        | Ppat_open ({ txt = mod_lid; _ }, p) ->
            let acc = self#record_mod_lid mod_lid acc in
            self#pattern p acc
        | _ -> super#pattern pat acc

      method! core_type ty acc =
        match ty.ptyp_desc with
        | Ptyp_constr ({ txt = Ldot (mod_lid, _); _ }, args) ->
            let acc = self#record_mod_lid mod_lid acc in
            List.fold_left (fun acc t -> self#core_type t acc) acc args
        | Ptyp_package ({ txt = Ldot (mod_lid, _); _ }, constrs) ->
            let acc = self#record_mod_lid mod_lid acc in
            List.fold_left (fun acc (_, t) -> self#core_type t acc) acc constrs
        | _ -> super#core_type ty acc

      method! module_expr me ((locals, _) as acc) =
        match me.pmod_desc with
        | Pmod_ident { txt; _ } -> self#record_mod_lid txt acc
        | Pmod_functor (Named ({ txt = Some name; _ }, mty), body) ->
            let acc = self#module_type mty acc in
            self#with_locals
              { locals with local_modules = String_set.add name locals.local_modules }
              self#module_expr body acc
        | Pmod_structure items ->
            let _, refs =
              List.fold_left
                (fun (locals, refs) item ->
                  let bindings = local_bindings_of_structure_item item in
                  match item.pstr_desc with
                  | Pstr_value (Recursive, _) | Pstr_recmodule _ ->
                      let locals' = add_local_bindings bindings locals in
                      self#structure_item item (locals', refs)
                  | _ ->
                      let _, refs = self#structure_item item (locals, refs) in
                      (add_local_bindings bindings locals, refs))
                acc items
            in
            (locals, refs)
        | _ -> super#module_expr me acc

      method! class_expr ce ((locals, _) as acc) =
        match ce.pcl_desc with
        | Pcl_fun (_, default_opt, pat, body) ->
            let acc = Option.fold ~none:acc ~some:(fun e -> self#expression e acc) default_opt in
            let acc = self#pattern pat acc in
            self#with_locals (add_local_bindings (pattern_bindings pat) locals) self#class_expr body acc
        | Pcl_let (Nonrecursive, vbs, body) ->
            let acc = List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs in
            let bindings =
              List.fold_left (fun b vb -> merge_bindings b (pattern_bindings vb.pvb_pat)) empty_bindings vbs
            in
            self#with_locals (add_local_bindings bindings locals) self#class_expr body acc
        | Pcl_let (Recursive, vbs, body) ->
            let bindings =
              List.fold_left (fun b vb -> merge_bindings b (pattern_bindings vb.pvb_pat)) empty_bindings vbs
            in
            let locals' = add_local_bindings bindings locals in
            let acc =
              self#with_locals locals'
                (fun vbs acc -> List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs)
                vbs acc
            in
            self#with_locals locals' self#class_expr body acc
        | _ -> super#class_expr ce acc
    end
  in
  snd (collector#expression expr (empty_locals, empty_refs))

let rec wildcard_shadowed_pattern ~shadowed_values ~shadowed_modules pat =
  let recurse = wildcard_shadowed_pattern ~shadowed_values ~shadowed_modules in
  match pat.ppat_desc with
  | Ppat_var { txt; _ } when String_set.mem txt shadowed_values -> { pat with ppat_desc = Ppat_any }
  | Ppat_alias (p, { txt; _ }) when String_set.mem txt shadowed_values -> recurse p
  | Ppat_alias (p, name) -> { pat with ppat_desc = Ppat_alias (recurse p, name) }
  | Ppat_unpack { txt = Some name; loc = name_loc } when String_set.mem name shadowed_modules ->
      { pat with ppat_desc = Ppat_unpack { txt = None; loc = name_loc } }
  | Ppat_tuple pats -> { pat with ppat_desc = Ppat_tuple (List.map recurse pats) }
  | Ppat_array pats -> { pat with ppat_desc = Ppat_array (List.map recurse pats) }
  | Ppat_construct (lid, Some (newtypes, p)) ->
      { pat with ppat_desc = Ppat_construct (lid, Some (newtypes, recurse p)) }
  | Ppat_variant (lbl, Some p) -> { pat with ppat_desc = Ppat_variant (lbl, Some (recurse p)) }
  | Ppat_record (fields, closed) ->
      { pat with ppat_desc = Ppat_record (List.map (fun (lid, p) -> (lid, recurse p)) fields, closed) }
  | Ppat_or (p1, p2) -> { pat with ppat_desc = Ppat_or (recurse p1, recurse p2) }
  | Ppat_constraint (p, ty) -> { pat with ppat_desc = Ppat_constraint (recurse p, ty) }
  | Ppat_lazy p -> { pat with ppat_desc = Ppat_lazy (recurse p) }
  | Ppat_exception p -> { pat with ppat_desc = Ppat_exception (recurse p) }
  | Ppat_open (lid, p) -> { pat with ppat_desc = Ppat_open (lid, recurse p) }
  | Ppat_var _ | Ppat_unpack _ | Ppat_any | Ppat_constant _ | Ppat_interval _
  | Ppat_construct (_, None)
  | Ppat_variant (_, None)
  | Ppat_type _ | Ppat_extension _ ->
      pat

let shadowed_sets refs =
  let shadowed_values =
    Longident_set.fold
      (fun lid acc -> match lid with Lident name -> String_set.add name acc | Ldot _ | Lapply _ -> acc)
      refs.ref_values String_set.empty
  in
  let shadowed_modules =
    Longident_set.fold
      (fun lid acc ->
        match lid with
        | Ldot (mod_lid, _) -> (
            match root_module_of_longident mod_lid with Some root -> String_set.add root acc | None -> acc)
        | Lident _ | Lapply _ -> acc)
      refs.ref_values refs.ref_modules
  in
  (shadowed_values, shadowed_modules)
