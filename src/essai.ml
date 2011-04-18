(* Essai *)
open Lwt 


let rec duppy (i: Xmlm.input) o : unit Lwt.t = 
  lwt __input = Xmlm.input i in 
  lwt _ = Xmlm.output o __input in 
  duppy i o 

let copy () =
  let ic = Unix.openfile Sys.argv.(1) [ Unix.O_RDONLY ] 0o777 in
  let oc = Unix.openfile Sys.argv.(2) [ Unix.O_WRONLY; Unix.O_CREAT ] 0o777 in
  
  let lwt_ic = Lwt_io.of_unix_fd ~mode:Lwt_io.input ic in
  let lwt_oc = Lwt_io.of_unix_fd ~mode:Lwt_io.output oc in
  
  let i : Xmlm.input = Xmlm.make_input (`Channel lwt_ic) in 
  let o = Xmlm.make_output (`Channel lwt_oc) in 
  
  catch 
    (fun () -> duppy i o) 
    (fun _ -> return ()) >>= fun _ -> Lwt_io.close lwt_ic >>= fun _ -> Lwt_io.close lwt_oc


let _ = 
  Lwt_main.run (copy ())
