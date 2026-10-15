module M = Map.Make(Int)
type policy = Gtc | Ioc | Fok | Post_only
type limits = { max_position : int; max_open_quantity : int; max_order_notional : int64 }
type account = { id : int; position : int; cash : int64; halted : bool; limits : limits }
type request =
  | Place of { account : int; id : int; side : Book.side; price : int; quantity : int; policy : policy }
  | Cancel of { account : int; id : int }
  | Halt of int
  | Resume of int
type rejection = Unknown_account | Halted | Unauthorized | Limit | Would_cross | Cannot_fill | Self_trade | Engine of Book.rejection
type status = Accepted | Rejected of rejection
type t = { book : Book.t; accounts : account M.t; owners : int M.t }
let book t = t.book
let accounts t = List.map snd (M.bindings t.accounts)
let orders t = Book.bids t.book @ Book.asks t.book
let create xs =
  let rec loop acc = function
    | [] -> Ok { book = Book.empty; accounts = acc; owners = M.empty }
    | (id, limits) :: rest ->
      if id < 0 || M.mem id acc || limits.max_position <= 0 || limits.max_position > 1_000_000_000
         || limits.max_open_quantity <= 0 || limits.max_open_quantity > 1_000_000_000
         || limits.max_order_notional <= 0L then Error "invalid or duplicate account/limits"
      else loop (M.add id { id; position = 0; cash = 0L; halted = false; limits } acc) rest
  in loop M.empty xs
let owned t account (o : Book.order) = M.find_opt o.id t.owners = Some account
let bounded_cash a b =
  let c = Int64.add a b in
  if (b > 0L && c < a) || (b < 0L && c > a) then None else Some c
let apply t request =
  let reject r = t, Rejected r, [] in
  let account_id = match request with Place x -> x.account | Cancel x -> x.account | Halt a | Resume a -> a in
  match M.find_opt account_id t.accounts with
  | None -> reject Unknown_account
  | Some a ->
    match request with
    | Halt _ ->
      let book = List.fold_left (fun b (o : Book.order) -> let b, _, _ = Book.apply b (Book.Cancel o.id) in b)
          t.book (List.filter (owned t a.id) (orders t)) in
      { t with book; accounts = M.add a.id { a with halted = true } t.accounts }, Accepted, []
    | Resume _ -> { t with accounts = M.add a.id { a with halted = false } t.accounts }, Accepted, []
    | Cancel x ->
      if M.find_opt x.id t.owners <> Some a.id then reject Unauthorized else
      let book, status, trades = Book.apply t.book (Book.Cancel x.id) in
      (match status with Book.Accepted -> { t with book }, Accepted, trades | Book.Rejected r -> reject (Engine r))
    | Place x ->
      if a.halted then reject Halted else
      let candidate, status, trades = Book.apply t.book (Book.Submit { id=x.id; side=x.side; price=x.price; quantity=x.quantity }) in
      match status with
      | Book.Rejected r -> reject (Engine r)
      | Book.Accepted ->
        let own = List.filter (owned t a.id) (orders t) in
        let reserved side = List.fold_left (fun n (o : Book.order) -> if o.side = side then n + o.quantity else n) 0 own in
        let signed_quantity = if x.side = Book.Buy then x.quantity else -x.quantity in
        let worst = a.position + signed_quantity + (if x.side = Book.Buy then reserved Book.Buy else -(reserved Book.Sell)) in
        if Int64.mul (Int64.of_int x.price) (Int64.of_int x.quantity) > a.limits.max_order_notional
           || abs worst > a.limits.max_position
           || reserved Book.Buy + reserved Book.Sell + x.quantity > a.limits.max_open_quantity then reject Limit
        else if x.policy = Post_only && trades <> [] then reject Would_cross
        else if x.policy = Fok && Book.total_traded trades <> x.quantity then reject Cannot_fill
        else if List.exists (fun (tr : Book.trade) -> M.find tr.maker_id t.owners = a.id) trades then reject Self_trade
        else
          let candidate = if x.policy = Ioc then let b, _, _ = Book.apply candidate (Book.Cancel x.id) in b else candidate in
          let owners = M.add x.id a.id t.owners in
          let update acc id position cash =
            match acc with None -> None | Some acc ->
              let old = M.find id acc in
              match bounded_cash old.cash cash with None -> None | Some cash ->
                Some (M.add id { old with position = old.position + position; cash } acc)
          in
          let ledger = List.fold_left (fun acc (tr : Book.trade) ->
              let lots = if x.side = Book.Buy then tr.quantity else -tr.quantity in
              let cash = Int64.mul (Int64.of_int tr.price) (Int64.of_int lots) in
              let acc = update acc a.id lots (Int64.neg cash) in
              update acc (M.find tr.maker_id owners) (-lots) cash) (Some t.accounts) trades in
          match ledger with None -> reject Limit | Some accounts -> { book = candidate; accounts; owners }, Accepted, trades
let check_invariants t =
  match Book.check_invariants t.book with Error e -> Error e | Ok () ->
  let positions = List.fold_left (fun n a -> Int64.add n (Int64.of_int a.position)) 0L (accounts t) in
  (* Summing paired ledger entries modulo 2^64 also verifies conservation when
     intermediate sums would exceed the signed representation. *)
  let cash = List.fold_left (fun n a -> Int64.add n a.cash) 0L (accounts t) in
  if positions <> 0L || cash <> 0L then Error "ledger conservation violated"
  else if List.exists (fun (o : Book.order) -> not (M.mem o.id t.owners)) (orders t) then Error "missing order owner"
  else if List.exists (fun a ->
    let own = List.filter (owned t a.id) (orders t) in
    let reserved side = List.fold_left (fun n (o : Book.order) -> if o.side = side then n + o.quantity else n) 0 own in
    let buys = reserved Book.Buy and sells = reserved Book.Sell in
    abs a.position > a.limits.max_position || a.position + buys > a.limits.max_position
    || a.position - sells < -a.limits.max_position || buys + sells > a.limits.max_open_quantity
    || (a.halted && own <> [])) (accounts t) then Error "account limits violated"
  else Ok ()
