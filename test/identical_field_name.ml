[@@@ocaml.warning "-30-42"]

type foo = { field : int }
and bar = { field : string }
[@@deriving visitors {
    name = "iter_foobar";
    variety = "iter";
    monomorphic = ["env"]
},
    visitors { variety = "map"; monomorphic = ["env"]},
    visitors { variety = "reduce"; monomorphic = ["env"]},
    visitors { variety = "mapreduce"; monomorphic = ["env"]}
]
