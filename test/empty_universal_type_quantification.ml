(* This fails with visitors 20210608 and OCaml 5.3. *)
(* Error: broken invariant in parsetree: Explicit universal type quantification cannot be empty. *)
(* Reported by Opale Sjöstedt <opale.sjostedt@gmail.com> *)
type t = Leaf of int | Node of t * t
[@@deriving visitors { variety = "map"; monomorphic = [ "'env" ] }]
