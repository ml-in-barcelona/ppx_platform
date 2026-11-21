open Ppxlib
module String_set = Set.Make (String)

let rec collect_pattern_bindings acc pat =
  match pat.ppat_desc with
  | Ppat_var { txt; _ } -> String_set.add txt acc
  | Ppat_alias (p, { txt; _ }) -> collect_pattern_bindings (String_set.add txt acc) p
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
  | Ppat_type _ | Ppat_unpack _ | Ppat_extension _ ->
      acc

let pattern_bindings pat = collect_pattern_bindings String_set.empty pat
let add_pattern pat locals = String_set.union locals (pattern_bindings pat)
let add_value_bindings vbs locals = List.fold_left (fun acc vb -> add_pattern vb.pvb_pat acc) locals vbs

let rec bindings_of_structure_item item =
  match item.pstr_desc with
  | Pstr_value (_, vbs) -> add_value_bindings vbs String_set.empty
  | Pstr_primitive vd -> String_set.singleton vd.pval_name.txt
  | Pstr_include { pincl_mod = { pmod_desc = Pmod_structure items; _ }; _ }
  | Pstr_extension (({ txt = "private"; _ }, PStr items), _) ->
      structure_bindings items
  | _ -> String_set.empty

and structure_bindings items =
  List.fold_left (fun acc item -> String_set.union acc (bindings_of_structure_item item)) String_set.empty items

let class_structure_bindings cls_str =
  List.fold_left
    (fun acc field -> match field.pcf_desc with Pcf_val (name, _, _) -> String_set.add name.txt acc | _ -> acc)
    (pattern_bindings cls_str.pcstr_self) cls_str.pcstr_fields

let collect_free_in_expr ~outer expr =
  let collector =
    object (self)
      inherit [String_set.t * String_set.t] Ast_traverse.fold as super

      method private with_bound :
          'a.
          String_set.t ->
          ('a -> String_set.t * String_set.t -> String_set.t * String_set.t) ->
          'a ->
          String_set.t * String_set.t ->
          String_set.t * String_set.t =
        fun bound' fn x (bound, refs) ->
          let _, refs = fn x (bound', refs) in
          (bound, refs)

      method private record name ((bound, refs) as acc) =
        if String_set.mem name outer && not (String_set.mem name bound) then (bound, String_set.add name refs) else acc

      method! expression expr ((bound, _) as acc) =
        match expr.pexp_desc with
        | Pexp_ident { txt = Lident name; _ } -> self#record name acc
        | Pexp_let (Nonrecursive, vbs, body) ->
            let acc = List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs in
            self#with_bound (add_value_bindings vbs bound) self#expression body acc
        | Pexp_let (Recursive, vbs, body) ->
            let bound' = add_value_bindings vbs bound in
            let acc =
              self#with_bound bound'
                (fun vbs acc -> List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs)
                vbs acc
            in
            self#with_bound bound' self#expression body acc
        | Pexp_letop { let_; ands; body } ->
            let ops = let_ :: ands in
            let acc =
              List.fold_left
                (fun acc bop ->
                  let acc = self#record bop.pbop_op.txt acc in
                  self#expression bop.pbop_exp acc)
                acc ops
            in
            let bound' = List.fold_left (fun acc bop -> add_pattern bop.pbop_pat acc) bound ops in
            self#with_bound bound' self#expression body acc
        | Pexp_function (params, _, body) ->
            let bound', refs =
              List.fold_left
                (fun (bound, refs) param ->
                  match param.pparam_desc with
                  | Pparam_val (_, default_opt, pat) ->
                      let _, refs =
                        Option.fold ~none:(bound, refs) ~some:(fun e -> self#expression e (bound, refs)) default_opt
                      in
                      (add_pattern pat bound, refs)
                  | Pparam_newtype _ -> (bound, refs))
                acc params
            in
            let _, refs =
              match body with
              | Pfunction_body e -> self#expression e (bound', refs)
              | Pfunction_cases (cases, _, _) -> self#cases cases (bound', refs)
            in
            (bound, refs)
        | Pexp_for (pat, e1, e2, _, body) ->
            let acc = self#expression e1 acc in
            let acc = self#expression e2 acc in
            self#with_bound (add_pattern pat bound) self#expression body acc
        | Pexp_open ({ popen_expr = { pmod_desc = Pmod_structure items; _ } as me; _ }, body) ->
            let acc = self#module_expr me acc in
            self#with_bound (String_set.union bound (structure_bindings items)) self#expression body acc
        | _ -> super#expression expr acc

      method! class_structure cls_str ((bound, _) as acc) =
        let bound' = String_set.union bound (class_structure_bindings cls_str) in
        List.fold_left
          (fun acc field ->
            match field.pcf_desc with
            | Pcf_val (_, _, Cfk_concrete (_, init)) -> self#expression init acc
            | _ -> self#with_bound bound' self#class_field field acc)
          acc cls_str.pcstr_fields

      method! case case ((bound, _) as acc) =
        self#with_bound (add_pattern case.pc_lhs bound)
          (fun () acc ->
            let acc = Option.fold ~none:acc ~some:(fun g -> self#expression g acc) case.pc_guard in
            self#expression case.pc_rhs acc)
          () acc

      method! module_expr me ((bound, _) as acc) =
        match me.pmod_desc with
        | Pmod_structure items ->
            let _, refs =
              List.fold_left
                (fun (bound, refs) item ->
                  let bound' = String_set.union bound (bindings_of_structure_item item) in
                  match item.pstr_desc with
                  | Pstr_value (Recursive, _) -> self#structure_item item (bound', refs)
                  | _ ->
                      let _, refs = self#structure_item item (bound, refs) in
                      (bound', refs))
                acc items
            in
            (bound, refs)
        | _ -> super#module_expr me acc

      method! class_expr ce ((bound, _) as acc) =
        match ce.pcl_desc with
        | Pcl_fun (_, default_opt, pat, body) ->
            let acc = Option.fold ~none:acc ~some:(fun e -> self#expression e acc) default_opt in
            self#with_bound (add_pattern pat bound) self#class_expr body acc
        | Pcl_let (Nonrecursive, vbs, body) ->
            let acc = List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs in
            self#with_bound (add_value_bindings vbs bound) self#class_expr body acc
        | Pcl_let (Recursive, vbs, body) ->
            let bound' = add_value_bindings vbs bound in
            let acc =
              self#with_bound bound'
                (fun vbs acc -> List.fold_left (fun acc vb -> self#value_binding vb acc) acc vbs)
                vbs acc
            in
            self#with_bound bound' self#class_expr body acc
        | _ -> super#class_expr ce acc
    end
  in
  snd (collector#expression expr (String_set.empty, String_set.empty))
