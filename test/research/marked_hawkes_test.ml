open Marked_hawkes
let get = function Ok x -> x | Error e -> failwith e
let check b s = if not b then failwith s
let near x y = abs_float (x -. y) < 1e-9 *. max 1. (abs_float y)
let p = {baseline_buy=2.;baseline_sell=3.;buy_buy=0.2;buy_sell=0.4;sell_buy=0.3;sell_sell=0.1;decay=1.}
let () =
  check (near (get (branching_radius p)) 0.5) "spectral radius";
  check (Result.is_error (validate {p with buy_buy=1.})) "supercritical radius";
  check (Result.is_error (validate {p with buy_buy=0.;sell_sell=0.;buy_sell=2.;sell_buy=0.5})) "critical cross excitation";
  check (get (validate {p with buy_buy=0.;sell_sell=0.;buy_sell=20.;sell_buy=0.}) = ()) "subcritical triangular matrix";
  check (near (get (branching_radius {p with buy_buy=0.;sell_sell=0.;buy_sell=1e300;sell_buy=1e-300})) 1.) "unbalanced cross-term spectral radius";
  check (Result.is_error (validate {p with buy_buy=0.;sell_sell=0.;buy_sell=1e300;sell_buy=1e-300})) "unbalanced critical matrix";
  check (Result.is_error (validate {p with decay=2.;buy_buy=1.99999999;sell_sell=1.99999999;
    buy_sell=1e308;sell_buy=Float.next_after 0. 1.})) "normalization underflow rejected";
  let tiny = {baseline_buy=1e-200;baseline_sell=1e-200;buy_buy=0.;sell_sell=0.;
    buy_sell=1e100;sell_buy=0.;decay=1e-200} in
  let tiny_residuals = get (compensator_increments tiny
    [{time=0.;side=Book.Sell};{time=1e-200;side=Book.Buy}]) in
  (match tiny_residuals with [_;r] ->
    check (abs_float (r.component_increment /. 1e-100 -. 1.) < 1e-12) "kernel underflow continuous limit"
    | _ -> failwith "tiny residual count");
  let events = [{time=0.5;side=Book.Buy};{time=1.;side=Book.Sell};{time=1.5;side=Book.Buy}] in
  let e = exp (-0.5) in
  let expected = log 2. +. log (3. +. 0.3 *. e)
    +. log (2. +. 0.2 *. e *. e +. 0.4 *. e) -. 10.
    -. 0.5 *. ((1. -. exp (-1.5)) +. (1. -. exp (-1.)) +. (1. -. e)) in
  check (near (get (log_likelihood p ~horizon:2. events)) expected) "direct marked likelihood";
  let residuals = get (compensator_increments p events) in
  (match residuals with
   | [a;b;c] ->
       check (near a.component_increment 1. && near a.total_increment 2.5) "first residual";
       check (near b.component_increment (3. +. 0.3 *. (1. -. e))) "sell includes earlier buy";
       check (near b.total_increment (2.5 +. 0.5 *. (1. -. e))) "total residual";
       check (near c.component_increment (2. +. 0.2 *. (1. -. e *. e) +. 0.4 *. (1. -. e))) "buy includes intervening sell"
   | _ -> failwith "residual count");
  check (near (get (log_likelihood p ~horizon:2. [])) (-10.)) "empty likelihood";
  check (Result.is_error (log_likelihood p ~horizon:2. [{time=1.;side=Book.Buy};{time=1.;side=Book.Sell}])) "simultaneous events rejected";
  let independent = {p with buy_buy=0.;buy_sell=0.;sell_buy=0.;sell_sell=0.} in
  check (near (get (log_likelihood independent ~horizon:2. events)) (2. *. log 2. +. log 3. -. 10.)) "independent Poisson limit";
  let simulate seed = get (simulate ~seed ~max_events:20000 ~max_candidates:30000 ~horizon:1000. p) in
  check (simulate 7 = simulate 7) "seed determinism";
  (* Both columns of A sum to .5, so the aggregate is exactly a univariate
     Hawkes process with baseline 5, excitation .5 and decay 1. *)
  let count = ref 0 in
  for seed = 1 to 40 do
    let events = simulate seed in
    count := !count + List.length events;
    let residuals = get (compensator_increments p events) in
    check (List.for_all (fun r -> r.component_increment >= 0. && r.total_increment >= 0.) residuals) "nonnegative residuals";
    check (Float.is_finite (get (log_likelihood p ~horizon:1000. events))) "finite stress likelihood";
    let unary = get (Analytics.Hawkes.compensator_increments
      Analytics.Hawkes.{baseline=5.;excitation=0.5;decay=1.}
      (List.map (fun e -> e.time) events)) in
    List.iter2 (fun r u -> check (near r.total_increment u) "aggregate compensator equality") residuals unary
  done;
  let expected = 10000. -. 10. *. (1. -. exp (-500.)) in
  check (abs_float (float_of_int !count /. 40. -. expected) < 0.04 *. expected) "aggregate finite-window moment";
  check (Result.is_error (Marked_hawkes.simulate ~seed:3 ~max_events:1 ~max_candidates:100 ~horizon:100. p)) "bounded events";
  check (Result.is_error (Marked_hawkes.simulate ~seed:3 ~max_events:10000 ~max_candidates:1 ~horizon:100. p)) "bounded candidates";
  Printf.printf "marked Hawkes passed: 40 seeds, %d events, direct formulas and aggregate residual identity\n" !count
