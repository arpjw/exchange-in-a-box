let ok = function Ok x -> x | Error message -> failwith message
let expect condition message = if not condition then failwith message
let venue ?(fee=0) ?(latency=0) name : Router.venue = {name;fee_ticks=fee;latency_penalty_ticks=latency}
let add state venue instrument id side price quantity =
  let next, outcome = Engine.apply state {Engine.timestamp=0L;venue;instrument;command=Book.Submit {id;side;price;quantity}} in
  expect (outcome=Engine.Applied(Book.Accepted,[])) "fixture unexpectedly matched or rejected";
  next
let test_examples () =
  let state = add Engine.empty "B" "ABC" 1 Book.Sell 100 3 in
  let state = add state "A" "ABC" 1 Book.Sell 101 2 in
  let state = add state "A" "ABC" 2 Book.Sell 101 4 in
  let venues = [venue ~fee:1 "B";venue "A"] in
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Buy ~quantity:8 ~venues) in
  expect (List.map (fun (x:Router.fill)->x.venue,x.maker_id,x.quantity) p.trace = ["A",1,2;"A",2,4;"B",1,2]) "tie, FIFO, or partial allocation";
  expect (p.total_cost=808L && p.filled=8 && p.unfilled=0) "example totals";
  expect (ok (Router.plan state ~instrument:"ABC" ~side:Buy ~quantity:8 ~venues:(List.rev venues))=p) "input order changes result";
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Buy ~quantity:20 ~venues) in
  expect (p.unfilled=11 && p.filled=9 && p.total_cost=909L) "insufficient depth";
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Sell ~quantity:1 ~venues) in
  expect (p.trace=[] && p.unfilled=1 && p.total_cost=0L) "wrong side depth";
  let p = ok (Router.plan state ~instrument:"OTHER" ~side:Buy ~quantity:1 ~venues) in
  expect (p.unfilled=1) "instrument isolation";
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Buy ~quantity:1 ~venues:[]) in
  expect (p.unfilled=1) "empty venue list";
  let state = add Engine.empty "A" "ABC" 1 Book.Buy 105 5 in
  let state = add state "B" "ABC" 1 Book.Buy 103 5 in
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Sell ~quantity:6 ~venues:[venue ~latency:3 "A";venue "B"]) in
  expect (List.map (fun (x:Router.fill)->x.venue,x.quantity) p.trace=["B",5;"A",1] && p.total_cost= -617L) "sell proceeds or latency sign";
  let p = ok (Router.plan state ~instrument:"ABC" ~side:Sell ~quantity:1 ~venues:[venue ~fee:(-5) "A";venue "B"]) in
  expect (p.total_cost= -110L) "rebate sign"
let test_invalid () =
  let plan ?(quantity=1) ?(instrument="ABC") venues = Router.plan Engine.empty ~instrument ~side:Buy ~quantity ~venues in
  List.iter (fun result -> expect (Result.is_error result) "invalid request accepted")
    [plan ~quantity:0 [];plan ~quantity:(-1) [];plan ~quantity:1_000_000_001 [];
     plan ~instrument:"" [];plan ~instrument:"bad space" [];plan [venue ""];
     plan [venue "A";venue "A"];plan [venue ~latency:(-1) "A"];
     plan [venue ~fee:max_int "A"];plan [venue ~fee:min_int "A"];
     plan [venue ~latency:max_int "A"]];
  let state=add Engine.empty "A" "ABC" 1 Book.Sell 1_000_000_000 1_000_000_000 in
  let p=ok (Router.plan state ~instrument:"ABC" ~side:Buy ~quantity:1_000_000_000 ~venues:[venue ~fee:1_000_000_000 ~latency:1_000_000_000 "A"]) in
  expect (p.total_cost=3_000_000_000_000_000_000L) "maximum total overflow"
let oracle curves target =
  let rec enumerate remaining = function
    | [] -> if remaining=0 then Some 0L else None
    | curve::rest ->
        let best = ref None in
        for q=0 to min remaining (Array.length curve-1) do
          match enumerate (remaining-q) rest with
          | None -> ()
          | Some tail -> let cost=Int64.add curve.(q) tail in
              best := Some (match !best with None->cost | Some previous->min previous cost)
        done;
        !best in
  match enumerate target curves with Some cost->cost | None->failwith "oracle infeasible"
let test_optimality () =
  for seed=0 to 499 do
    let rng=Random.State.make [|seed;908|] in
    let side=if seed mod 2=0 then Book.Buy else Book.Sell in
    let maker_side=if side=Book.Buy then Book.Sell else Book.Buy in
    let venues=List.init 3 (fun i->venue ~fee:(Random.State.int rng 7-3) ~latency:(Random.State.int rng 4) (string_of_int i)) in
    let state=ref Engine.empty and curves=ref [] and available=ref 0 in
    List.iter (fun (v:Router.venue)->
      let orders=List.init 3 (fun id->id,95+Random.State.int rng 11,1+Random.State.int rng 2) in
      List.iter (fun (id,price,quantity)->state:=add !state v.name "ABC" id maker_side price quantity) orders;
      let orders=List.sort (fun (ia,pa,_) (ib,pb,_)->let c=if side=Book.Buy then compare pa pb else compare pb pa in if c=0 then compare ia ib else c) orders in
      let units=List.concat_map (fun (_,price,quantity)->List.init quantity (fun _->(if side=Book.Buy then price else -price)+v.fee_ticks+v.latency_penalty_ticks)) orders in
      available:= !available+List.length units;
      let curve=Array.make (List.length units+1) 0L in
      List.iteri (fun i cost->curve.(i+1)<-Int64.add curve.(i) (Int64.of_int cost)) units;
      curves:=curve:: !curves) venues;
    let quantity=1+Random.State.int rng 25 in
    let plan=ok (Router.plan !state ~instrument:"ABC" ~side ~quantity ~venues) in
    let filled=min quantity !available in
    expect (plan.filled=filled && plan.unfilled=quantity-filled) "optimality fill count";
    expect (plan.total_cost=oracle !curves filled) "not brute-force optimal";
    expect (plan=ok (Router.plan !state ~instrument:"ABC" ~side ~quantity ~venues:(List.rev venues))) "random route not reproducible";
    let consumed=Hashtbl.create 3 in
    List.iter (fun (fill:Router.fill)->
      let pending=match Hashtbl.find_opt consumed fill.venue with Some xs->xs | None->let b=Engine.book !state ~venue:fill.venue ~instrument:"ABC" in if side=Buy then Book.asks b else Book.bids b in
      match pending with
      | []->failwith "fill exceeds venue depth"
      | (maker:Book.order)::rest->
          expect (maker.id=fill.maker_id && maker.sequence=fill.maker_sequence && fill.quantity>0 && fill.quantity<=maker.quantity) "maker priority or quantity violated";
          Hashtbl.replace consumed fill.venue (if maker.quantity=fill.quantity then rest else {maker with quantity=maker.quantity-fill.quantity}::rest)) plan.trace
  done;
  print_endline "router optimality passed: 500 seeded books checked against exhaustive allocations"
let test_stress () =
  let venues=List.init 50 (fun i->venue ~fee:(i mod 5) ~latency:(i mod 3) (Printf.sprintf "V%02d" i)) in
  let state=ref Engine.empty in
  List.iter (fun (v:Router.venue)->for id=0 to 999 do state:=add !state v.name "ABC" id Book.Sell (2000-id) 1 done) venues;
  let p=ok (Router.plan !state ~instrument:"ABC" ~side:Buy ~quantity:60_000 ~venues) in
  expect (p.filled=50_000 && p.unfilled=10_000 && List.length p.trace=50_000) "large depth allocation";
  expect (p=ok (Router.plan !state ~instrument:"ABC" ~side:Buy ~quantity:60_000 ~venues:(List.rev venues))) "stress reproducibility";
  print_endline "router stress passed: 50000 makers across 50 venues"
let ()=test_examples ();test_invalid ();test_optimality ();test_stress ()
