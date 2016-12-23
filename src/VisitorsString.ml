open String

(* [split_on_char c s] splits the string [s] into substrings delimited
   by the character [c]. *)

(* Copied from OCaml 4.04. *)

let split_on_char sep s =
  let r = ref [] in
  let j = ref (length s) in
  for i = length s - 1 downto 0 do
    if unsafe_get s i = sep then begin
      r := sub s (i + 1) (!j - i - 1) :: !r;
      j := i
    end
  done;
  sub s 0 !j :: !r
