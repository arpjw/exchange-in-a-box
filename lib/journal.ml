type recovery = { events : Engine.event list; state : Engine.t; outcomes : Engine.outcome list; ignored_tail : bool }
let header = "EXCHANGE-JOURNAL\t1\n"
let payload index (e : Engine.event) =
  let command = match e.command with
    | Book.Cancel id -> Printf.sprintf "C\t%d" id
    | Book.Submit { id; side; price; quantity } -> Printf.sprintf "S\t%d\t%s\t%d\t%d" id (if side = Book.Buy then "B" else "S") price quantity in
  Printf.sprintf "%d\t%Ld\t%s\t%s\t%s" index e.timestamp e.venue e.instrument command
let checksum s = Digest.to_hex (Digest.string s)
let read path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (in_channel_length ic))
let decode expected line =
  match List.rev (String.split_on_char '\t' line) with
  | hash :: reversed ->
      let parts = List.rev reversed in
      let body = String.concat "\t" parts in
      if checksum body <> hash then failwith "record checksum mismatch";
      (match parts with
       | index :: timestamp :: venue :: instrument :: command ->
           if int_of_string index <> expected then failwith "record sequence mismatch";
           let command = match command with
             | ["C"; id] -> Book.Cancel (int_of_string id)
             | ["S"; id; side; price; quantity] ->
                 let side = match side with "B" -> Book.Buy | "S" -> Book.Sell | _ -> failwith "invalid side" in
                 Book.Submit { id = int_of_string id; side; price = int_of_string price; quantity = int_of_string quantity }
             | _ -> failwith "invalid command" in
           { Engine.timestamp = Int64.of_string timestamp; venue; instrument; command }
       | _ -> failwith "invalid record")
  | _ -> failwith "invalid record"
let parse contents =
  let h = String.length header in
  if String.length contents < h || String.sub contents 0 h <> header then failwith "missing or unsupported journal header";
  let rec loop index start events =
    match String.index_from_opt contents start '\n' with
    | None -> List.rev events, start, start <> String.length contents
    | Some stop ->
        let e = decode index (String.sub contents start (stop - start)) in
        loop (index + 1) (stop + 1) (e :: events) in
  loop 0 h []
let protect f = try Ok (f ()) with Sys_error s | Failure s | Invalid_argument s -> Error s
let recover path = protect (fun () ->
  let events, _, ignored_tail = parse (read path) in
  let state, outcomes = Engine.replay events in { events; state; outcomes; ignored_tail })
let write path flags contents =
  let oc = open_out_gen (Open_binary :: flags) 0o600 path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc contents; flush oc)
let validate_event (e : Engine.event) =
  if String.contains e.venue '\t' || String.contains e.venue '\n' || String.contains e.instrument '\t' || String.contains e.instrument '\n' then failwith "route contains journal delimiters"
let record index e = let body = payload index e in body ^ "\t" ^ checksum body ^ "\n"
type writer = { channel : out_channel; mutable next : int; mutable closed : bool; mutable failed : string option }
let open_writer path = protect (fun () ->
  let exists = Sys.file_exists path in
  let events =
    if exists then (
      let events, _, tail = parse (read path) in
      if tail then failwith "incomplete tail: repair before open";
      events)
    else [] in
  let state, outcomes = Engine.replay events in
  let channel = open_out_gen [Open_binary; Open_wronly; Open_creat; Open_append] 0o600 path in
  (try if not exists then (output_string channel header; flush channel)
   with exn -> close_out_noerr channel; raise exn);
  { channel; next = List.length events; closed = false; failed = None },
  { events; state; outcomes; ignored_tail = false })
let ensure_open writer =
  match writer.failed with
  | Some message -> failwith ("journal writer failed: " ^ message)
  | None -> if writer.closed then failwith "journal writer is closed"
let io writer f =
  try f () with
  | (Sys_error message | Failure message | Invalid_argument message) as exn ->
      writer.failed <- Some message;
      writer.closed <- true;
      close_out_noerr writer.channel;
      raise exn
let append_writer writer event = protect (fun () ->
  ensure_open writer;
  validate_event event;
  if writer.next = max_int then failwith "journal sequence exhausted";
  let line = record writer.next event in
  io writer (fun () -> output_string writer.channel line);
  writer.next <- writer.next + 1)
let flush_writer writer = protect (fun () ->
  ensure_open writer;
  io writer (fun () -> flush writer.channel))
let close_writer writer = protect (fun () ->
  match writer.failed with
  | Some message -> failwith ("journal writer failed: " ^ message)
  | None -> if not writer.closed then (
      io writer (fun () -> close_out writer.channel);
      writer.closed <- true))
let append path event =
  match protect (fun () -> validate_event event) with
  | Error _ as error -> error
  | Ok () ->
      match open_writer path with
      | Error _ as error -> error
      | Ok (writer, _) ->
          match append_writer writer event with
          | Error _ as error -> ignore (close_writer writer); error
          | Ok () -> close_writer writer

let repair_tail path = protect (fun () ->
  let contents = read path in
  let _, valid_length, tail = parse contents in
  if tail then (
    let temporary = Filename.temp_file ~temp_dir:(Filename.dirname path) ".journal-repair-" ".tmp" in
    Fun.protect ~finally:(fun () -> if Sys.file_exists temporary then Sys.remove temporary)
      (fun () -> write temporary [Open_wronly; Open_trunc] (String.sub contents 0 valid_length); Sys.rename temporary path));
  tail)
