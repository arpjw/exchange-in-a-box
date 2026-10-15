let assert_ok = function Ok x -> x | Error e -> failwith e
let () =
  let config : Scenario.config = {
    seed = 42; events = 250; agents = 8; initial_price = 10_000; impact_lots = 200 } in
  let native = assert_ok (Scenario.run config) in
  let traced, frames = assert_ok (Scenario.trace ~max_samples:30 config) in
  assert (native.accepted = traced.accepted);
  assert (native.rejected = traced.rejected);
  assert (native.volume = traced.volume);
  assert (native.final_mid = traced.final_mid);
  assert (snd (List.hd (List.rev frames)) == traced.state);
  assert (fst (List.hd frames) = 0);
  assert (fst (List.hd (List.rev frames)) = config.events);
  List.iter (fun (_, state) -> assert_ok (Risk.check_invariants state)) frames;
  let session = Lab.make_session () in
  let before = Lab.snapshot session in
  let after = Lab.place session ~account:2 ~side:"buy" ~price:10_001 ~quantity:50 ~policy:"ioc" in
  assert (before <> after);
  let report = Lab.scenario ~seed:42 ~events:250 ~agents:8 ~impact_lots:200 in
  let open Yojson.Basic.Util in
  assert (report |> member "volume" |> to_int = native.volume);
  assert (report |> member "frames" |> to_list |> List.length = List.length (snd (assert_ok (Scenario.trace ~max_samples:120 config))));
  let pair = Lab.intervention ~seed:1000 ~events:150 ~shock_lots:0 ~regime:"passive" in
  assert (pair |> member "difference" |> to_float = 0.);
  let route = Lab.route ~side:"buy" ~quantity:350 ~fees:[0;0;0] in
  assert (route |> member "filled" |> to_int = 350);
  print_endline "browser lab native parity passed"
