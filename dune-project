(lang dune 3.9)

(using melange 0.1)

(cram enable)

(name ppx_platform)

(license MIT)

(maintainers "David Sancho <dsnxmoreno@gmail.com>")

(authors "David Sancho <dsnxmoreno@gmail.com>")

(source
 (github ml-in-barcelona/ppx_platform))

(generate_opam_files true)

(implicit_transitive_deps false)

(package
 (name ppx_platform)
 (synopsis "Platform-specific code for native and Melange builds")
 (description
  "A ppx rewriter that keeps one OCaml codebase for native and Melange builds: let%melange_only, [@melange_only], [@native_only] and match%platform pick the code that each target compiles.")
 (depends
  (ocaml (>= 4.14.1))
  (ppxlib (>= 0.36.0))
  (melange (>= 3.0.0))
  (reason :with-test)
  (ocamlformat
   (and
    (= 0.28.1)
    :with-test))))
