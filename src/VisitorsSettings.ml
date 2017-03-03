open VisitorsString
open List
let sprintf = Printf.sprintf
open Parsetree
open Ppx_deriving
open VisitorsPlugin
open VisitorsAnalysis
open VisitorsGeneration

(* -------------------------------------------------------------------------- *)

(* We can generate classes that adhere to several distinct schemes, listed
   below. These schemes differ only in the re-building code that is executed
   after the recursive calls. In [iter], this code does nothing. In [map], it
   reconstructs a data structure. In [endo], it also reconstructs a data
   structure, but attempts to preserve sharing. In [reduce], it combines the
   results of the recursive calls using a monoid operation. In [fold], this
   code is missing; it is represented by a virtual method. *)

type scheme =
  | Iter
  | Map
  | Endo
  | Reduce
  | MapReduce
  | Fold

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

  (* The classes that the visitor should inherit. *)
  val ancestors: Longident.t list

  (* [concrete] controls whether the generated class should be concrete or
     virtual. By default, it is virtual. *)
  val concrete: bool

  (* If [irregular] is [true], the regularity check is suppressed; this allows
     a local parameterized type to be instantiated. The definition of ['a t]
     can then refer to [int t]. However, in most situations, this will lead to
     ill-typed generated code. The generated code should be well-typed if [t]
     is always instantiated in the same manner, e.g., if there are references
     to [int t] but not to other instances of [t]. *)
  val irregular: bool

  (* If [public] is present, then every method is declared private, except
     the methods whose name appears in the list [public]. *)
  val public: string list option

  (* If [polymorphic] is [true], then (possibly polymorphic) type annotations
     for methods are generated. The function [poly], applied to the name of a
     type variable (without its quote), tells whether this type variable
     should receive monomorphic or polymorphic treatment. In the former case,
     this type variable is dealt with via a visitor method; in the latter
     case, it is dealt with via a visitor function. *)
  val polymorphic: bool
  val poly: tyvar -> bool

end

(* -------------------------------------------------------------------------- *)

(* [unquote alpha] removes a leading quote in the string [alpha], it there is
   one. *)

let unquote alpha =
  let n = String.length alpha in
  if n > 0 && alpha.[0] = '\'' then
    String.sub alpha 1 (n-1)
  else
    alpha

(* -------------------------------------------------------------------------- *)

(* The supported varieties. *)

(* Note that [mapreduce] must appear in this list before [map], as shorter
   prefixes must be tested last. *)

let supported = [
    "mapreduce", MapReduce;
    "map", Map;
    "iter", Iter;
    "endo", Endo;
    "reduce", Reduce;
    "fold", Fold;
  ]

let valid_varieties =
  "iter, map, endo, reduce, mapreduce, fold,\n\
   iter2, map2, reduce2, mapreduce2, fold2"

let invalid_variety loc =
  raise_errorf ~loc
    "%s: invalid variety. The valid varieties are\n\
     %s."
    plugin valid_varieties

(* [parse_variety] takes a variety, which could be "iter", "map2", etc. and
   returns a pair of a scheme and an arity. *)

let parse_variety loc (s : string) : scheme * int =
  (* A loop over [supported] tries each supported variety in turn. *)
  let rec loop supported s =
    match supported with
    | (p, scheme) :: supported ->
        if prefix p s then
          let s = remainder p s in
          let i = if s = "" then 1 else int_of_string s in
          if i <= 0 then failwith "negative integer"
          else scheme, i
        else
          loop supported s
    | [] ->
        failwith "unexpected prefix"
  in
  (* Start the loop and handle errors. *)
  try
    loop supported s
  with Failure _ ->
    invalid_variety loc

(* -------------------------------------------------------------------------- *)

let must_be_valid_mod_longident loc m =
  if not (is_valid_mod_longident m) then
    raise_errorf ~loc
      "%s: %s is not a valid module identifier." plugin m

let must_be_valid_class_longident loc c =
  if not (is_valid_class_longident c) then
    raise_errorf ~loc
      "%s: %s is not a valid class identifier." plugin c

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

  let name = ref None
  let arity = ref 1 (* dummy: [variety] is mandatory; see below *)
  let scheme = ref Iter (* dummy: [variety] is mandatory; see below *)
  let variety = ref None
  let ancestors = ref []
  let concrete = ref false
  let irregular = ref false
  let polymorphic = ref false
  let poly = ref (fun _ -> false)
  let public = ref None

  (* Parse every option. *)

  let () =
    iter (fun (o, e) ->
      let loc = e.pexp_loc in
      match o with
      | "ancestors" ->
           ancestors := strings e
      | "concrete" ->
           concrete := bool e
      | "irregular" ->
          irregular := bool e
      | "name" ->
          name := Some (string e)
      | "polymorphic" ->
          (* The [polymorphic] parameter can be a Boolean constant or a list
             of type variable names. If [true], then all type variables are
             considered polymorphic. If a list of type variables, then only
             the variables in the list are considered polymorphic. *)
          begin match Arg.bool e, Arg.list Arg.string e with
          | Ok b, Error _ ->
              polymorphic := b;
              poly := (fun _ -> b)
          | Error _, Ok alphas ->
              let alphas = List.map unquote alphas in
              polymorphic := true;
              poly := (fun alpha -> List.mem alpha alphas)
          | Error _, Error _ ->
              raise_errorf ~loc:e.pexp_loc "%s: Boolean or string list expected" plugin
          | Ok _, Ok _ ->
              assert false
          end
      | "public" ->
          public := Some (strings e)
      | "variety" ->
          let v = string e in
          variety := Some v;
          let s, a = parse_variety loc v in
          scheme := s;
          arity := a;
          (* [endo] is supported only at arity 1. *)
          if s = Endo && a > 1 then
            invalid_variety loc
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
  let scheme = !scheme
  let ancestors = !ancestors
  let concrete = !concrete
  let irregular = !irregular
  let polymorphic = !polymorphic
  let poly = !poly
  let public = !public

  (* Perform sanity checking. *)

  (* The parameter [variety] is not optional. *)
  let variety =
    match !variety with
    | None ->
        raise_errorf ~loc
          "%s: please specify the variety of the generated class.\n\
           e.g. [@@deriving visitors { variety = \"iter\" }]" plugin
    | Some variety ->
        variety

  (* The parameter [name] is optional. If it is absent, then [variety]
     is used as its default value. *)
  let name =
    match !name with
    | Some name ->
        (* We expect [name] to be a valid class name. *)
        if classify name <> LIDENT then
          raise_errorf ~loc
            "%s: %s is not a valid class name."
            plugin name;
        name
    | None ->
        variety

  (* Every string in the list [ancestors] must be a valid (long) class
     identifier. *)
  let () =
    iter (must_be_valid_class_longident loc) ancestors

  (* When the variety is [iter], the class [VisitorsRuntime.iter] is an
     implicit ancestor, and similarly for every variety. *)
  let ancestors =
    map Longident.parse (("VisitorsRuntime." ^ variety) :: ancestors)

  (* If [scheme] is [Fold], then [polymorphic] must be [false]. Indeed,
     we currently cannot generate polymorphic type annotations in that
     case, as we cannot guess the return types of the visitor methods. *)
  let () =
    if scheme = Fold && polymorphic then
      raise_errorf ~loc
        "%s: cannot generate polymorphic\n\
         type annotations for fold visitors."
        plugin

end
