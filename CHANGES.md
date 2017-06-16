# Changes

## 2017/04/20

* New settings `visit_prefix`, `build_prefix`, and `fail_prefix` can be used
  to control which prefixes are used in generated method names. (This feature
  was suggested by Philip Hölzenspies.)

## 2017/04/04

* Extended backward compatibility to OCaml 4.02.2. (Thanks to Benjamin Farinier.)

## 2017/03/17

* New attributes `@build` and `@@build` can be attached to record type
  declarations and data constructors, so as to alter the construction code that
  is used in `map`, `endo`, and `mapreduce` visitors. See the documentation for
  details. (This feature was suggested by Reuben Rowe.)

## 2017/03/15

* New attributes `@name` and `@@name` can be attached to types, type declarations,
  and data constructors, so as to alter the names of the generated methods. See
  the documentation for details. (This feature was suggested by Reuben Rowe.)

## 2017/03/08

* A new option `polymorphic = true` allows generating visitor methods with
  polymorphic types. With `polymorphic = true`, a type variable `'a` is
  handled by a visitor *function* `visit_'a`, which is passed as an argument
  to every visitor method; whereas, with `polymorphic = false`, a type
  variable `'a` is handled by a virtual visitor *method* `visit_'a`.
  With `polymorphic = true`, visitor classes compose better,
  and irregular algebraic data types are supported.
  See the documentation for more details.
  (This feature was suggested by Reuben Rowe.)

## 2017/03/03

* A new option `data = false` allows suppressing the generation of visitor
  methods for data constructors. This makes the generated visitor slightly
  simpler and faster, but less customizable.

* A new option `nude = true` allows *not* implicitly inheriting the class
  `VisitorsRuntime.<variety>`.

## 2017/02/15

* `Makefile.preprocess` is now installed with the package, so users can rely on it
  without needing to copy it. See the documentation for instructions.

## 2017/02/13

* Added a new variety of visitors, `mapreduce`. This visitor computes a pair of a
  data structure (like a `map` visitor) and a summary (like a `reduce` visitor).
  This can be used to annotate every tree node with information about the
  subtree that lies below it. See the documentation for an example.

## 2017/02/09

* Documentation: added a new subsection on OCaml objects,
  entitled "Where the expressiveness of OCaml's type system falls short".
  This section explains why `map` cannot be a subclass of `fold`,
  even though it should be.

## 2017/01/31

* Documentation: added an example of constructing a lexicographic ordering.

* Documentation: discussed generating visitors for existing types and `ppx_import`.

## 2017/01/26

* Initial release.