(** Derived order-book state and a univariate exponential Hawkes process. *)

type quote =
  { bid_price : int
  ; bid_quantity : int
  ; ask_price : int
  ; ask_quantity : int
  ; spread : int
  ; imbalance : float
  ; microprice : float
  }

val quote : Book.t -> quote option

module Hawkes : sig
  type parameters = { baseline : float; excitation : float; decay : float }

  val validate : parameters -> (unit, string) result
  val branching_ratio : parameters -> float
  val log_likelihood : parameters -> horizon:float -> float list -> (float, string) result
  val compensator_increments :
    parameters -> float list -> (float list, string) result
end
