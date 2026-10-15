type quote =
  { bid_price : int
  ; bid_quantity : int
  ; ask_price : int
  ; ask_quantity : int
  ; spread : int
  ; imbalance : float
  ; microprice : float
  }

let rec size_at price (orders : Book.order list) =
  match orders with
  | order :: rest when order.Book.price = price -> order.quantity + size_at price rest
  | _ -> 0

let quote book =
  match Book.bids book, Book.asks book with
  | bid :: _, ask :: _ ->
      let bid_quantity = size_at bid.price (Book.bids book) in
      let ask_quantity = size_at ask.price (Book.asks book) in
      let total = float_of_int bid_quantity +. float_of_int ask_quantity in
      Some
        { bid_price = bid.price
        ; bid_quantity
        ; ask_price = ask.price
        ; ask_quantity
        ; spread = ask.price - bid.price
        ; imbalance =
            (float_of_int bid_quantity -. float_of_int ask_quantity) /. total
        ; microprice =
            (float_of_int ask.price *. float_of_int bid_quantity
             +. float_of_int bid.price *. float_of_int ask_quantity)
            /. total
        }
  | _ -> None

module Hawkes = struct
  type parameters = { baseline : float; excitation : float; decay : float }

  let finite x = Float.is_finite x

  let validate p =
    if not (finite p.baseline && finite p.excitation && finite p.decay) then
      Error "parameters must be finite"
    else if p.baseline <= 0. || p.excitation < 0. || p.decay <= 0. then
      Error "baseline and decay must be positive; excitation must be nonnegative"
    else if p.excitation >= p.decay then
      Error "stationary branching ratio must be below one"
    else Ok ()

  let branching_ratio p = p.excitation /. p.decay

  let validate_times ~horizon times =
    if not (finite horizon) || horizon < 0. then Error "invalid horizon"
    else
      let rec loop previous = function
        | [] -> Ok ()
        | time :: rest ->
            if not (finite time) || time < 0. || time > horizon
               || time <= previous
            then Error "events must be finite, strictly increasing, and within the horizon"
            else loop time rest
      in
      loop neg_infinity times

  let log_likelihood p ~horizon times =
    match validate p, validate_times ~horizon times with
    | Error message, _ | _, Error message -> Error message
    | Ok (), Ok () ->
        let rec sum previous excitation_state log_intensity integral = function
          | [] ->
              log_intensity -. p.baseline *. horizon
              -. p.excitation /. p.decay *. integral
          | time :: rest ->
              let decayed =
                if previous = neg_infinity then 0.
                else excitation_state *. exp (-.p.decay *. (time -. previous))
              in
              let intensity = p.baseline +. p.excitation *. decayed in
              let contribution = -.expm1 (-.p.decay *. (horizon -. time)) in
              sum time (decayed +. 1.)
                (log_intensity +. log intensity)
                (integral +. contribution) rest
        in
        Ok (sum neg_infinity 0. 0. 0. times)

  let compensator_increments p times =
    match validate p with
    | Error message -> Error message
    | Ok () ->
        let horizon = match List.rev times with [] -> 0. | x :: _ -> x in
        (match validate_times ~horizon times with
         | Error message -> Error message
         | Ok () ->
             let rec loop previous state reversed = function
               | [] -> Ok (List.rev reversed)
               | time :: rest ->
                   let delta = time -. previous in
                   let increment =
                     p.baseline *. delta
                     +. p.excitation *. state /. p.decay
                        *. (-.expm1 (-.p.decay *. delta))
                   in
                   let state = state *. exp (-.p.decay *. delta) +. 1. in
                   loop time state (increment :: reversed) rest
             in
             loop 0. 0. [] times)
end
