open VisitorsString
open List
let sprintf = Printf.sprintf
open Parsetree
open Ppx_deriving
open VisitorsAnalysis
open VisitorsGeneration

(* -------------------------------------------------------------------------- *)

(* The name of our [ppx_deriving] plugin. *)

let plugin =
  "visitors"

(* -------------------------------------------------------------------------- *)

(* We can generate several classes: as of now, [iter], [map], [reduce]. They
   are mostly identical, and differ only in the code that is executed after
   the recursive calls. In [iter], this code does nothing. In [map], it
   reconstructs a data structure. In [reduce], it combines the results of
   the recursive calls using a monoid operation. *)

type scheme =
  | Iter
  | Map
  | Reduce

(* -------------------------------------------------------------------------- *)

(* The parameters that can be set by the user. *)

module type SETTINGS = sig

  (* The type declarations that we are processing. *)
  val decls: type_declaration list

  (* The name of the generated class. *)
  val name: classe

  (* The arity of the generated code, e.g., 1 if one wishes to generate [iter]
     and [map], 2 if one wishes to generate [iter2] and [map2], and so on. *)
  val arity: int

  (* The scheme of visitor that we wish to generate (see the definition of
     the type [scheme] above). *)
  val scheme: scheme

  (* [variety] combines the information in [scheme] and [arity]. It is just
     the string provided by the user. *)
  val variety: string

  (* If [final] is false, which is the default, we generate OCaml classes.
     If [final] is true, we generate nests of mutually recursive functions.
     This requires that there be no virtual methods. *)
  val final: bool

  (* The type variables that should be treated as nonlocal types. Following
     OCaml's convention, the name of a type variable does not include a
     leading quote. *)
  val freeze: string list

  (* If [irregular] is [true], the regularity check is suppressed; this allows
     a local parameterized type to be instantiated. The definition of ['a t]
     can then refer to [int t]. However, in most situations, this will lead to
     ill-typed generated code. The generated code should be well-typed if [t]
     is always instantiated in the same manner, e.g., if there are references
     to [int t] but not to other instances of [t]. *)
  val irregular: bool

  (* A list of module names that should be searched for nonlocal functions,
     such as [List.iter]. The modules that appear first in the list are
     searched last. *)
  val path: Longident.t list

end

(* -------------------------------------------------------------------------- *)

(* [parse_variety] takes a variety, which could be "iter", "map2", etc. and
   returns a pair of a scheme and an arity. *)

let rec parse_variety ps (s : string) : scheme * int =
  match (ps : (string * scheme) list) with
  | (p, scheme) :: ps ->
      if prefix p s then
        let s = remainder p s in
        let i = if s = "" then 1 else int_of_string s in
        if i <= 0 then failwith "negative integer"
        else scheme, i
      else
        parse_variety ps s
  | [] ->
      failwith "unexpected prefix"

let parse_variety loc (s : string) : scheme * int =
  try
    parse_variety ["map", Map; "iter", Iter; "reduce", Reduce] s
  with
  | Failure _ ->
      raise_errorf ~loc
      "%s: invalid variety.\n\
       A valid variety is iter, map, reduce, iter2, map2, reduce2, etc." plugin

(* -------------------------------------------------------------------------- *)

(* The option processing code constructs a module of type [SETTINGS]. *)

module Parse (O : sig
  val loc: Location.t
  val decls: type_declaration list
  val options: (string * expression) list
end)
: SETTINGS
= struct
  open O

  (* Set up a few parsers. *)

  let bool = Arg.get_expr ~deriver:plugin Arg.bool
  let string = Arg.get_expr ~deriver:plugin Arg.string
  let strings = Arg.get_expr ~deriver:plugin (Arg.list Arg.string)

  (* Default values. *)

  let arity = ref 1 (* dummy: [variety] is mandatory; see below *)
  let final = ref false
  let freeze = ref []
  let irregular = ref false
  let names = ref [] (* dummy: [name] is mandatory; see below *)
  let path = ref []
  let scheme = ref Iter (* dummy: [variety] is mandatory; see below *)
  let variety = ref None

  (* Parse every option. *)

  let () =
    iter (fun (o, e) ->
      let loc = e.pexp_loc in
      match o with
      | "final" ->
           final := bool e
      | "freeze" ->
           freeze := strings e
      | "irregular" ->
          irregular := bool e
      | "name" ->
          names := string e :: !names;
      | "path" ->
          path := strings e
      | "variety" ->
          let v = string e in
          variety := Some v;
          let s, a = parse_variety loc v in
          scheme := s;
          arity := a
      | _ ->
          (* We could emit a warning, instead of an error, if we find an
             unsupported option. That might be preferable for forward
             compatibility. That said, I am not sure that ignoring unknown
             options is a good idea; it might cause us to generate code
             that does not work as expected by the user. *)
          raise_errorf ~loc "%s: option %s is not supported." plugin o
    ) options

  (* Export the results. *)

  let decls = decls
  let arity = !arity
  let final = !final
  let freeze = !freeze
  let irregular = !irregular
  let path = !path
  let scheme = !scheme

  (* Perform sanity checking. *)

  (* The parameter [name] is not optional. Also, it should be given multiple
     times. So, we first accumulate a list of names, then check that this list
     has length 1. *)
  let name =
    if length !names = 0 then
      raise_errorf ~loc
        "%s: please specify the name of the generated class.\n\
         e.g. [@@deriving visitors { name = \"traverse\" }]" plugin;
    if length !names > 1 then
      raise_errorf ~loc
        "%s: please specify only ONE name for the generated class." plugin;
    match !names with
    | [ name ] ->
       (* If [final] is true, we expect [name] to be a valid module name;
          otherwise, we expect it to be a valid class name. *)
       let expected = if final then UIDENT else LIDENT in
       if classify name <> expected then
          raise_errorf ~loc
            "%s: %s is not a valid %s name."
            plugin name
            (if final then "module" else "class");
        name
    | []
    | _ :: _ :: _ ->
        assert false (* already checked length *)

  (* The parameter [variety] is not optional. *)
  let variety =
    match !variety with
    | None ->
        raise_errorf ~loc
          "%s: please specify the variety of the generated class.\n\
           e.g. [@@deriving visitors { variety = \"iter\" }]" plugin
    | Some variety ->
        variety

  (* Check that every string in the list [path] is a valid (long) module
     identifier. *)
  let () =
    iter (fun m ->
      if not (is_valid_mod_longident m) then
        raise_errorf ~loc
          "%s: %s is not a valid module identifier." plugin m
    ) path

  (* We always open [VisitorsRuntime], but allow it to be shadowed by
     user-specified modules. *)
  let path =
    map Longident.parse ("VisitorsRuntime" :: path)

end