open Js_of_ocaml

let session = ref (Lab.make_session ())
let output value = Js.string (Lab.encode value)
let from_js value = Js.to_string value
let () =
  Js.export "ExchangeBox"
    (object%js
      method reset = session := Lab.make_session (); output (Lab.snapshot !session)
      method current = output (Lab.snapshot !session)
      method place account side price quantity policy =
        output (Lab.place !session ~account ~side:(from_js side) ~price ~quantity ~policy:(from_js policy))
      method cancel account id = output (Lab.apply !session (Risk.Cancel {account; id}))
      method halt account = output (Lab.apply !session (Risk.Halt account))
      method resume account = output (Lab.apply !session (Risk.Resume account))
      method scenario seed events agents impact =
        output (Lab.scenario ~seed ~events ~agents ~impact_lots:impact)
      method intervention seed events shock regime =
        output (Lab.intervention ~seed ~events ~shock_lots:shock ~regime:(from_js regime))
      method route side quantity fee_a fee_b fee_c =
        output (Lab.route ~side:(from_js side) ~quantity ~fees:[fee_a; fee_b; fee_c])
    end)
