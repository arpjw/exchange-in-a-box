type event = { timestamp : int64; venue : string; instrument : string; command : Book.command }
type outcome = Applied of Book.status * Book.trade list | Invalid_route | Time_regression
module Routes = Map.Make (struct type t = string * string let compare = compare end)
type t = { clock : int64; books : Book.t Routes.t }
let empty = { clock = 0L; books = Routes.empty }
let clock t = t.clock
let book t ~venue ~instrument =
  Option.value (Routes.find_opt (venue, instrument) t.books) ~default:Book.empty
let valid_name s =
  String.length s > 0 && String.length s <= 128 &&
  String.for_all (function 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '-' | '.' -> true | _ -> false) s
let apply t e =
  if not (valid_name e.venue && valid_name e.instrument) then t, Invalid_route
  else if e.timestamp < t.clock then t, Time_regression
  else
    let b, status, trades = Book.apply (book t ~venue:e.venue ~instrument:e.instrument) e.command in
    { clock = e.timestamp; books = Routes.add (e.venue, e.instrument) b t.books }, Applied (status, trades)
let replay events =
  let t, outputs = List.fold_left (fun (t, out) e -> let t, o = apply t e in t, o :: out) (empty, []) events in
  t, List.rev outputs
let check_invariants t =
  Routes.fold (fun _ b acc -> match acc with Error _ -> acc | Ok () -> Book.check_invariants b) t.books (Ok ())
let schedule ~latency ~drop events =
  let rec collect i acc = function
    | [] -> Ok (List.map (fun (_, _, e) -> e) (List.sort (fun (ta, ia, _) (tb, ib, _) -> let c = Int64.compare ta tb in if c = 0 then Int.compare ia ib else c) acc))
    | e :: rest ->
        let delay = latency i in
        if e.timestamp < 0L || delay < 0L || delay > Int64.sub Int64.max_int e.timestamp then Error "negative or overflowing delivery time"
        else if drop i then collect (i + 1) acc rest
        else let timestamp = Int64.add e.timestamp delay in collect (i + 1) ((timestamp, i, { e with timestamp }) :: acc) rest
  in collect 0 [] events
