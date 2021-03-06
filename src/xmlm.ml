(*----------------------------------------------------------------------------
   copyright (c) 2007-2009, Daniel C. Bünzli. All rights reserved.
   Distributed under a BSD license, see license at the end of the file.
   Xmlm version 1.0.2
  ----------------------------------------------------------------------------*)

(*-- Lwt compliant
  
  william.le-ferrand@polytechnique.edu
  -----------------*)

open Lwt 
open Lwt_io

module Std_string = String
module Std_buffer = Buffer
    
type std_string = string
type std_buffer = Buffer.t
      
module type String = sig
  type t
  val empty : t
  val length : t -> int
  val append : t -> t -> t
  val lowercase : t -> t
  val iter : (int -> unit Lwt.t) -> t -> unit Lwt.t
  val of_string : std_string -> t
  val to_utf_8 : ('a -> std_string -> 'a Lwt.t) -> 'a -> t -> 'a Lwt.t
  val compare : t -> t -> int
end
      
module type Buffer = sig
  type string
  type t 
  exception Full
  val create : int -> t
  val add_uchar : t -> int -> unit
  val clear : t -> unit
  val contents : t -> string
  val length : t -> int
end

module type S = sig 
  type string 
  type encoding = [ 
    | `UTF_8 | `UTF_16 | `UTF_16BE | `UTF_16LE | `ISO_8859_1 | `US_ASCII ]
  type dtd = string option
  type name = string * string 
  type attribute = name * string
  type tag = name * attribute list
  type signal = [ `Dtd of dtd | `El_start of tag | `El_end | `Data of string ]
    
  val ns_xml : string 
  val ns_xmlns : string

  type pos = int * int 
  type error = [
    | `Max_buffer_size			
    | `Unexpected_eoi
    | `Malformed_char_stream
    | `Unknown_encoding of string
    | `Unknown_entity_ref of string				 
    | `Unknown_ns_prefix of string				
    | `Illegal_char_ref of string 
    | `Illegal_char_seq of string 
    | `Expected_char_seqs of string list * string
    | `Expected_root_element ]	

  exception Error of pos * error
  val error_message : error -> string      

  type source = [ 
  | `Channel of Lwt_io.input_channel 
  | `String of int * std_string 
  | `Fun of (unit -> int Lwt.t) ]

  type input 
	
  val make_input : ?enc:encoding option -> ?strip:bool -> 
                   ?ns:(string -> string option) -> 
		   ?entity: (string -> string option) -> source -> input
	  
  val input : input -> signal Lwt.t

  val input_tree : el:(tag -> 'a list -> 'a) -> data:(string -> 'a)  -> 
                   input -> 'a Lwt.t

  val input_doc_tree : el:(tag -> 'a list -> 'a) -> data:(string -> 'a) -> 
                       input -> (dtd * 'a) Lwt.t
    
  val peek : input -> signal Lwt.t
  val eoi : input -> bool Lwt.t
  val pos : input -> pos 

  type 'a frag = [ `El of tag * 'a list | `Data of string ]
  type dest = [ 
    | `Channel of Lwt_io.output_channel | `Buffer of std_buffer | `Fun of (int -> unit) ]

  type output
  val make_output : ?nl:bool -> ?indent:int option -> 
                    ?ns_prefix:(string -> string option) -> dest -> output

  val output : output -> signal -> unit Lwt.t
  val output_tree : ('a -> 'a frag) -> output -> 'a -> unit Lwt.t
  val output_doc_tree : ('a -> 'a frag) -> output -> (dtd * 'a) -> unit Lwt.t   
end


(* Unicode character lexers *)
      
exception Malformed                 (* for character stream, internal only. *)

let utf8_len = [|        (* Char byte length according to first UTF-8 byte. *)
  1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 
  1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 
  1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 
  1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 
  1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 
  1; 1; 1; 1; 1; 1; 1; 1; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 
  0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 
  0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 
  0; 0; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 2; 
  2; 2; 2; 2; 2; 2; 2; 2; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 3; 
  4; 4; 4; 4; 4; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0 |]
    
let uchar_utf8 i : int Lwt.t =
  lwt b0 = i () in
  begin 
    match utf8_len.(b0) with
      | 0 -> fail Malformed
      | 1 -> return b0
      | 2 ->
	lwt b1 = i () in
           if b1 lsr 6 != 0b10 then
	     fail Malformed 
	   else
	       return (((b0 land 0x1F) lsl 6) lor (b1 land 0x3F)) 
  | 3 ->
      lwt b1 = i () in
      lwt b2 = i () in
       if b2 lsr 6 != 0b10 then raise Malformed else
	begin match b0 with
	  | 0xE0 -> if b1 < 0xA0 || 0xBF < b1 then raise Malformed else ()
	  | 0xED -> if b1 < 0x80 || 0x9F < b1 then raise Malformed else ()
	  | _ -> if b1 lsr 6 != 0b10 then raise Malformed else ()
	end;
      return (((b0 land 0x0F) lsl 12) lor ((b1 land 0x3F) lsl 6) lor (b2 land 0x3F))
  | 4 -> 
      lwt b1 = i () in
      lwt b2 = i () in
      lwt b3 = i () in
      if  b3 lsr 6 != 0b10 || b2 lsr 6 != 0b10 then raise Malformed else
	begin match b0 with
	  | 0xF0 -> if b1 < 0x90 || 0xBF < b1 then raise Malformed else ()
	  | 0xF4 -> if b1 < 0x80 || 0x8F < b1 then raise Malformed else ()
	  | _ -> if b1 lsr 6 != 0b10 then raise Malformed else ()
	end;
        return (
	  ((b0 land 0x07) lsl 18) lor ((b1 land 0x3F) lsl 12) lor 
	    ((b2 land 0x3F) lsl 6) lor (b3 land 0x3F))
  | _ -> assert false	
  end
    
let int16_be i = 
  lwt b0 = i () in
  lwt b1 = i () in
  return ((b0 lsl 8) lor b1)
    
let int16_le i = 
  lwt b0 = i () in
  lwt b1 = i () in
  return ((b1 lsl 8) lor b0) 
    
let uchar_utf16 int16 i = 
  lwt c0 = int16 i in
  if c0 < 0xD800 || c0 > 0xDFFF then 
    return c0 
  else
    if c0 >= 0xDBFF then fail Malformed else
      lwt c1 = int16 i in return ((((c0 land 0x3FF) lsl 10) lor (c1 land 0x3FF)) + 0x10000)
    
let uchar_utf16be = uchar_utf16 int16_be
let uchar_utf16le = uchar_utf16 int16_le 
let uchar_byte i = i ()
let uchar_iso_8859_1 i = i ()
let uchar_ascii i = lwt b = i () in if b > 127 then fail Malformed else return b

(* Functorized streaming XML IO *)

module Make (String : String) (Buffer : Buffer with type string = String.t) = 
struct
  type string = String.t
	
  let str = String.of_string
  let str_eq s s' = (compare s s') = 0
  let str_empty s = (compare s String.empty) = 0
  let cat = String.append 
  let str_of_char u = 
    let b = Buffer.create 4 in 
    Buffer.add_uchar b u;
    Buffer.contents b

  module Ht = Hashtbl.Make (struct type t = string 
	                           let equal = str_eq
				   let hash = Hashtbl.hash end)
      
  let u_nl = 0x000A     (* newline *)
  let u_cr = 0x000D     (* carriage return *)
  let u_space = 0x0020  (* space *)
  let u_quot = 0x0022   (* quote *)
  let u_sharp = 0x0023  (* # *)
  let u_amp = 0x0026    (* & *)
  let u_apos = 0x0027   (* ' *)
  let u_minus = 0x002D  (* - *)
  let u_slash = 0x002F  (* / *)
  let u_colon = 0x003A  (* : *)
  let u_scolon = 0x003B (* ; *)
  let u_lt = 0x003C     (* < *)
  let u_eq = 0x003D     (* = *)
  let u_gt = 0x003E     (* > *)
  let u_qmark = 0x003F  (* ? *)
  let u_emark = 0x0021  (* ! *)
  let u_lbrack = 0x005B (* [ *)
  let u_rbrack = 0x005D (* ] *)
  let u_x = 0x0078      (* x *)
  let u_bom = 0xFEFF    (* BOM *)
  let u_9 = 0x0039      (* 9 *)
  let u_F = 0x0046      (* F *)
  let u_D = 0X0044      (* D *)
      
  let s_cdata = str "CDATA["      
  let ns_xml = str "http://www.w3.org/XML/1998/namespace"
  let ns_xmlns = str "http://www.w3.org/2000/xmlns/"      
  let n_xml = str "xml"
  let n_xmlns = str "xmlns"
  let n_space = str "space"
  let n_version = str "version"
  let n_encoding = str "encoding"
  let n_standalone = str "standalone"
  let v_yes = str "yes"
  let v_no = str "no"
  let v_preserve = str "preserve"
  let v_default = str "default"
  let v_version_1_0 = str "1.0"
  let v_version_1_1 = str "1.1"
  let v_utf_8 = str "utf-8"
  let v_utf_16 = str "utf-16"
  let v_utf_16be = str "utf-16be"
  let v_utf_16le = str "utf-16le"
  let v_iso_8859_1 = str "iso-8859-1"
  let v_us_ascii = str "us-ascii" 
  let v_ascii = str "ascii"
      
  let name_str (p,l) = if str_empty p then l else cat p (cat (str ":") l)

  (* Basic types and values *)

  type encoding = [ 
    | `UTF_8 | `UTF_16 | `UTF_16BE | `UTF_16LE | `ISO_8859_1 | `US_ASCII ]
  type dtd = string option
  type name = string * string 
  type attribute = name * string
  type tag = name * attribute list
  type signal = [ `Dtd of dtd | `El_start of tag | `El_end | `Data of string ]

  (* Input *)
    
  type pos = int * int 
  type error = [
    | `Max_buffer_size			
    | `Unexpected_eoi
    | `Malformed_char_stream
    | `Unknown_encoding of string
    | `Unknown_entity_ref of string				 
    | `Unknown_ns_prefix of string				
    | `Illegal_char_ref of string 
    | `Illegal_char_seq of string 
    | `Expected_char_seqs of string list * string
    | `Expected_root_element ]
	
  exception Error of pos * error

  
  let error_message e = 
    let bracket l v r = cat (str l) (cat v (str r)) in
    match e with
    | `Expected_root_element -> str "expected root element"
    | `Max_buffer_size -> str "maximal buffer size exceeded"
    | `Unexpected_eoi -> str "unexpected end of input"
    | `Malformed_char_stream -> str "malformed character stream"
    | `Unknown_encoding e -> bracket "unknown encoding (" e ")"
    | `Unknown_entity_ref e -> bracket "unknown entity reference (" e ")"
    | `Unknown_ns_prefix e -> bracket "unknown namespace prefix (" e ")"
    | `Illegal_char_ref s -> bracket "illegal character reference (#" s ")"
    | `Illegal_char_seq s ->
	bracket "character sequence illegal here (\"" s "\")"
    | `Expected_char_seqs (exps, fnd) -> 
	let exps = 
	  let exp acc v = cat acc (bracket "\"" v "\", ") in
	  List.fold_left exp String.empty exps
	in
	cat (str "expected one of these character sequence: ") 
	  (cat exps (bracket "found \"" fnd "\""))

  type limit =                                        (* XML is odd to parse. *)
    | Stag of name   (* '<' qname *) 
    | Etag of name   (* '</' qname whitespace* *) 
    | Pi of name     (* '<?' qname *) 
    | Comment        (* '<!--' *)
    | Cdata          (* '<![CDATA[' *)
    | Dtd            (* '<!' *) 
    | Text           (* other character *)
    | Eoi            (* End of input *)
	
  type input = 
    { enc : encoding option;                            (* Expected encoding. *)
      strip : bool;                (* Whitespace stripping default behaviour. *)
      fun_ns : string -> string option;                (* Namespace callback. *)
      fun_entity : string -> string option;     (* Entity reference callback. *)
      i : unit -> int Lwt.t;                                   (* Byte level input. *)
      mutable uchar : (unit -> int Lwt.t) -> int Lwt.t;       (* Unicode character lexer. *)
      mutable c : int;                                (* Character lookahead. *)
      mutable cr : bool;                          (* True if last u was '\r'. *)
      mutable line : int;                             (* Current line number. *)
      mutable col : int;                            (* Current column number. *)
      mutable limit : limit;                            (* Last parsed limit. *)
      mutable peek : signal;                             (* Signal lookahead. *)
      mutable stripping : bool;              (* True if stripping whitespace. *)
      mutable last_white : bool;              (* True if last char was white. *)
      mutable scopes : (name * string list * bool) list;
          (* Stack of qualified el. name, bound prefixes and strip behaviour. *)
      ns : string Ht.t;                            (* prefix -> uri bindings. *)
      ident : Buffer.t;                  (* Buffer for names and entity refs. *)
      data : Buffer.t; }          (* Buffer for character and attribute data. *)

  let err_input_tree = "input signal not `El_start or `Data"
  let err_input_doc_tree = "input signal not `Dtd"
  let err i e = raise (Error ((i.line, i.col), e))
  let err_illegal_char i u = err i (`Illegal_char_seq (str_of_char u))
  let err_expected_seqs i exps s = err i (`Expected_char_seqs (exps, s))
  let err_expected_chars i exps = 
    err i (`Expected_char_seqs (List.map str_of_char exps, str_of_char i.c))

      
  let u_eoi = max_int
  let u_start_doc = u_eoi - 1
  let u_end_doc = u_start_doc - 1
  let signal_start_stream = `Data String.empty

    type source = [ 
    | `Channel of Lwt_io.input_channel 
    | `String of int * std_string
    | `Fun of (unit -> int Lwt.t) ]

  let make_input ?(enc = None) ?(strip = false) ?(ns = fun _ -> None) 
                 ?(entity = fun _ -> None) src = 
    let i = match src with
      | `Fun f -> f 
      | `Channel ic ->
	(fun () -> 
	  Lwt_io.read_char ic >>= 
	    fun c -> return (Char.code c))
      | `String (pos, s) -> 
	let len = Std_string.length s in
	let pos = ref (pos - 1) in
	(fun () -> 
	  incr pos;
	  if !pos = len then 
	    fail End_of_file
	  else 
	    return (Char.code (Std_string.get s !pos)))
    in
    let bindings = 
      let h = Ht.create 15 in 
      Ht.add h String.empty String.empty;
      Ht.add h n_xml ns_xml;
      Ht.add h n_xmlns ns_xmlns;
      h
    in
    { enc = enc; strip = strip; fun_ns  = ns; fun_entity = entity;
      i = i; uchar = uchar_byte; c = u_start_doc; cr = false;
      line = 1; col = 0; limit = Text; peek = signal_start_stream; 
      stripping = strip; last_white = true; scopes = []; ns = bindings; 
      ident = Buffer.create 64; data = Buffer.create 1024; }

(* Bracketed non-terminals in comments refer to XML 1.0 non terminals *)

  let r : int -> int -> int -> bool = fun u a b -> a <= u && u <= b
  let is_white = function 0x0020 | 0x0009 | 0x000D | 0x000A -> true | _ -> false
  
  let is_char = function                                            (* {Char} *)
    | u when r u 0x0020 0xD7FF -> true
    | 0x0009 | 0x000A | 0x000D -> true
    | u when r u 0xE000 0xFFFD
    || r u 0x10000 0x10FFFF -> true
    | _ -> false

  let is_digit u = r u 0x0030 0x0039
  let is_hex_digit u = 
    r u 0x0030 0x0039 || r u 0x0041 0x0046 || r u 0x0061 0x0066
	  
  let comm_range u = r u 0x00C0 0x00D6           (* common to functions below *)
  || r u 0x00D8 0x00F6 || r u 0x00F8 0x02FF || r u 0x0370 0x037D 
  || r u 0x037F 0x1FFF || r u 0x200C 0x200D || r u 0x2070 0x218F
  || r u 0x2C00 0x2FEF || r u 0x3001 0xD7FF || r u 0xF900 0xFDCF 
  || r u 0xFDF0 0xFFFD || r u 0x10000 0xEFFFF
      
  let is_name_start_char = function        (* {NameStartChar} - ':' (XML 1.1) *)
    | u when r u 0x0061 0x007A || r u 0x0041 0x005A -> true  (* [a-z] | [A-Z] *)
    | u when is_white u -> false
    | 0x005F -> true                                                   (* '_' *)
    | u when comm_range u -> true 
    | _ -> false
	  
  let is_name_char = function                   (* {NameChar} - ':' (XML 1.1) *)
    | u when r u 0x0061 0x007A || r u 0x0041 0x005A -> true  (* [a-z] | [A-Z] *)
    | u when is_white u -> false
    | u when  r u 0x0030 0x0039 -> true                              (* [0-9] *)
    | 0x005F | 0x002D | 0x002E | 0x00B7 -> true                (* '_' '-' '.' *)
    | u when comm_range u || r u 0x0300 0x036F || r u 0x203F 0x2040 -> true
    | _ -> false

  let rec nextc i =                    
    if i.c = u_eoi then err i `Unexpected_eoi;
    if i.c = u_nl then (i.line <- i.line + 1; i.col <- 1) 
    else i.col <- i.col + 1;
    let f : unit -> int Lwt.t = i.i in 
    i.uchar f 
    >>= fun c -> i.c <- c ; 
    if not (is_char i.c) then raise Malformed; 
    (if i.cr && i.c = u_nl then
      begin
	lwt c = i.uchar i.i in
        i.c <- c;
      return () 
     end else return ())
    >>= fun () -> 
    (* cr nl business *)
    if i.c = u_cr then (i.cr <- true; i.c <- u_nl) else i.cr <- false;
    return () 
		    
	  
  let nextc_eof i = 
    catch
      (fun () -> nextc i)
      (fun e -> match e with
	| End_of_file -> i.c <- u_eoi; return ()
	| e -> fail e)

  let skip_white i =
    let rec loop = function 
      | true -> (nextc i >>= fun () -> loop (is_white i.c))
      | false -> return () in
    loop (is_white i.c)
  
  let skip_white_eof i = 
    let rec loop = function 
      | true -> (nextc_eof i >>= fun () -> loop (is_white i.c))
      | false -> return () in
    loop (is_white i.c)

  let accept i c = if i.c = c then nextc i else err_expected_chars i [ c ]

  let clear_ident i = Buffer.clear i.ident
  let clear_data i = Buffer.clear i.data
  let addc_ident i c = Buffer.add_uchar i.ident c
  let addc_data i c = Buffer.add_uchar i.data c

  let addc_data_strip i c = 
    if is_white c then i.last_white <- true else
    begin
      if i.last_white && Buffer.length i.data <> 0 then addc_data i u_space;
      i.last_white <- false;
      addc_data i c
    end
      
  let expand_name i (prefix, local) = 
    let external_ prefix = match i.fun_ns prefix with
    | None -> err i (`Unknown_ns_prefix prefix)
    | Some uri -> uri
    in
    try
      let uri = Ht.find i.ns prefix in 
      if not (str_empty uri) then (uri, local) else
      if str_empty prefix then String.empty, local else 
      (external_ prefix), local              (* unbound with xmlns:prefix="" *)
    with Not_found -> external_ prefix, local

  let find_encoding i =                                    (* Encoding mess. *)
    let reset uchar i = i.uchar <- uchar; i.col <- 0; nextc i in 
    match i.enc with
    | None ->                                 (* User doesn't know encoding. *)
	begin 
	  lwt _ = nextc i in 
	  match i.c with          
	| 0xFE ->                                           (* UTF-16BE BOM. *)
	  (lwt _ = nextc i in if i.c <> 0xFF then err i `Malformed_char_stream;
	  reset uchar_utf16be i 
	  >>= fun _ -> return true)                                 
	| 0xFF ->                                           (* UTF-16LE BOM. *)
	  (lwt _ = nextc i in if i.c <> 0xFE then err i `Malformed_char_stream;
	   reset uchar_utf16le i
	   >>= fun _ -> return true)   
        | 0xEF ->                                              (* UTF-8 BOM. *)
	    (lwt _ = nextc i in if i.c <> 0xBB then err i `Malformed_char_stream;
	     lwt _ = nextc i in if i.c <> 0xBF then err i `Malformed_char_stream;
	    reset uchar_utf8 i >>= fun _ -> return true)
	| 0x3C | _ ->                    (* UTF-8 or other, try declaration. *)
	    i.uchar <- uchar_utf8; 
	    return false  
	end
    | Some e ->                                      (* User knows encoding. *)
      lwt _ = begin match e with                              
	| `US_ASCII -> reset uchar_ascii i
	| `ISO_8859_1 -> reset uchar_iso_8859_1 i
	| `UTF_8 ->                                  (* Skip BOM if present. *)
	  lwt _ = reset uchar_utf8 i in if i.c = u_bom then (i.col <- 0; nextc i) else return ()
	| `UTF_16 ->                             (* Which UTF-16 ? look BOM. *)
	    lwt _ = nextc i in let b0 = i.c in
	    lwt _ = nextc i in let b1 = i.c in
	    begin match b0, b1 with                
	    | 0xFE, 0xFF -> reset uchar_utf16be i
	    | 0xFF, 0xFE -> reset uchar_utf16le i
	    | _ -> err i `Malformed_char_stream;
	    end
	| `UTF_16BE ->                               (* Skip BOM if present. *)
	    lwt _ = reset uchar_utf16be i in if i.c = u_bom then (i.col <- 0; nextc i) else return ()
	| `UTF_16LE ->
	    lwt _ = reset uchar_utf16le i in if i.c = u_bom then (i.col <- 0; nextc i) else return ()
 end in
	return true                                      (* Ignore xml declaration. *)


 let p_ncname i =
   
   clear_ident i;
   if not (is_name_start_char i.c) then 
     err_illegal_char i i.c
   else
     begin 
       addc_ident i i.c; lwt _ = nextc i in
     let rec loop = function 
	| false -> return ()
	| true -> addc_ident i i.c ; lwt _ = nextc i in loop (is_name_char i.c) in
     lwt _ = loop (is_name_char i.c) in
      return (Buffer.contents i.ident) 
   end

    
  let p_qname i =                                 (* {QName} (Namespace 1.1) *)
    lwt n  = p_ncname i in
  
  if i.c <> u_colon then return (String.empty, n) else (lwt _ = nextc i in lwt s = p_ncname i in return (n, s))
      
  let p_charref i =                             (* {CharRef}, '&' was eaten. *) 
    let c = ref 0 in
    clear_ident i;
    lwt _ = nextc i in
    lwt _ = if i.c = u_scolon then err i (`Illegal_char_ref String.empty) else
      lwt _ = 
      catch (fun () ->
	if i.c = u_x then 
	  begin 
	    addc_ident i i.c;
	    lwt _ = nextc i in
	  let rec loop = function
	    | false -> return ()
	    | true -> 
	      addc_ident i i.c;               
	      if not (is_hex_digit i.c) then raise Exit else 
	      c := !c * 16 + (if i.c <= u_9 then i.c - 48 else
	                      if i.c <= u_F then i.c - 55 else 
			      i.c - 87);
	      lwt _ = nextc i in loop (i.c <> u_scolon)
          in 
	  loop (i.c <> u_scolon) 
	  end
 else
  begin
    let rec loop = function 
      | false -> return ()
      | true -> 
	  addc_ident i i.c;
	    if not (is_digit i.c) then raise Exit else 
	    c := !c * 10 + (i.c - 48);
	    lwt _ = nextc i in loop (i.c <> u_scolon) in
  loop (i.c <> u_scolon)
 end)
	(fun e -> match e with 
	  | Exit -> 
	    c := -1; 
	    let rec loop = function 
	      | false -> return () ; 
	      | true -> addc_ident i i.c; lwt _ = nextc i in loop (i.c <> u_scolon) in
           loop (i.c <> u_scolon) 
	| e -> fail e) in return () in

lwt _ = nextc i in

match is_char !c with 
  | false -> err i (`Illegal_char_ref (Buffer.contents i.ident)) 
  | true ->  clear_ident i; addc_ident i !c; return (Buffer.contents i.ident)
    
	
  let predefined_entities = 
    let h = Ht.create 5 in
    let e k v = Ht.add h (str k) (str v) in
    e "lt" "<"; e "gt" ">"; e "amp" "&"; e "apos" "'"; e "quot" "\""; 
    h
      
  let p_entity_ref i =                        (* {EntityRef}, '&' was eaten. *)
    lwt ent = p_ncname i in
    lwt _ = accept i u_scolon in 
    catch 
      (fun () -> return (Ht.find predefined_entities ent))
      (fun e -> match e with
	| Not_found -> 
	 ( match i.fun_entity ent with
	    | Some s -> return s
	    | None -> err i (`Unknown_entity_ref ent) )
	| e -> fail e )

  let p_reference i =                                        (* {Reference} *)
    lwt _ = nextc i in if i.c = u_sharp then p_charref i else p_entity_ref i

  let p_attr_value i =                                   (* {S}? {AttValue} *)
    lwt _ = skip_white i in
    let delim = 
      if i.c = u_quot or i.c = u_apos then i.c else 
      err_expected_chars i [ u_quot; u_apos]
    in
    lwt _ = nextc i in
    lwt _ = skip_white i in
    clear_data i;
    i.last_white <- true;
    let rec loop = function 
      | false -> return ()
      | true -> 
        if i.c = u_lt then 
	  err_illegal_char i u_lt
	else
	  lwt _ = if i.c = u_amp then
	      (lwt pr = p_reference i in String.iter (fun p -> return (addc_data_strip i p)) pr)
	  else (addc_data_strip i i.c; nextc i) in
           loop (i.c <> delim)
 in
    lwt _ = loop (i.c <> delim) in
    lwt _ = nextc i in
    return (Buffer.contents i.data)

let p_attributes i =                            (* ({S} {Attribute})* {S}? *) 
    let rec aux i pre_acc acc = 
      if not (is_white i.c) then 
	return (pre_acc, acc)
      else
      begin
	lwt _ = skip_white i in
	if i.c = u_slash or i.c = u_gt then
	  return (pre_acc, acc)
	else 
	  begin 
	    lwt (prefix, local) as n = p_qname i in
	    lwt _ = skip_white i in
	    lwt _ = accept i u_eq in 
            lwt v = p_attr_value i in
             
	  let att = n, v in
	  if str_empty prefix && str_eq local n_xmlns then
	    begin  (* xmlns *)                                                
	      Ht.add i.ns String.empty v;
	      aux i (String.empty :: pre_acc) (att :: acc)
	    end
	  else if str_eq prefix n_xmlns then 
	    begin  (* xmlns:local *)                                        
	      Ht.add i.ns local v;
	      aux i (local :: pre_acc) (att :: acc)
	    end
	  else if str_eq prefix n_xml && str_eq local n_space then
	    begin  (* xml:space *)
	      if str_eq v v_preserve then i.stripping <- false else
	      if str_eq v v_default then i.stripping <- i.strip else ();
	      aux i pre_acc (att :: acc)
	    end
	  else
	    aux i pre_acc (att :: acc)
	end
      end
    in
    aux i [] []           (* Returns a list of bound prefixes and attributes *)

  let p_limit i =                                   (* Parses a markup limit *)
    
    
    lwt limit = 
      if i.c = u_eoi then
	return Eoi
      else
	if i.c <> u_lt then
	  return Text
	else 
	  begin
	    lwt _ = nextc i in
	   
	    if i.c = u_qmark then 
	      (lwt _ = nextc i in lwt qn = p_qname i in return (Pi qn))
	    else
	      if i.c = u_slash then 
		begin 
		  lwt _ = nextc i in 
		  lwt n = p_qname i in 
		  lwt _ = skip_white i in
		  return (Etag n)
		end
             else 
               if i.c = u_emark then 
		 begin 
		   lwt _ = nextc i in
		   if i.c = u_minus then 
	           (lwt _ = nextc i in lwt _ =  accept i u_minus in return Comment)
		   else
		     if i.c = u_D then
		       ( 
			 return Dtd) 
		     else
		       if i.c = u_lbrack then 
			 begin 
			   lwt _ = nextc i in
			 clear_ident i;
			 let rec loop = function 
			   | 0 -> return () 
			   | n -> addc_ident i i.c; lwt _ = nextc i in loop (n-1) in
                         lwt _ = loop 6 in
                 let cdata = Buffer.contents i.ident in 
		 if str_eq cdata s_cdata then
		   return Cdata
		 else
		   err_expected_seqs i [ s_cdata ] cdata
 end
	    else
	      err i (`Illegal_char_seq (cat (str "<!") (str_of_char i.c)))
	  end
	else 
         (
          lwt pq = p_qname i in
	  return (Stag pq))
      end in 
   i.limit <- limit ; 
   return () 	
    
  let rec skip_comment i =   (* {Comment}, '<!--' was eaten *)
    let rec loop = function 
      | false -> return () 
      | true -> lwt _ = nextc i in loop (i.c <> u_minus) in
    lwt _ = loop (i.c <> u_minus) in 
    lwt _ = nextc i in
    if i.c <> u_minus then
      skip_comment i
    else 
      begin 
	lwt _ = nextc i in
	if i.c <> u_gt then err_expected_chars i [ u_gt ];
	nextc_eof i
      end
      
  let rec skip_pi i =                          (* {PI}, '<?' qname was eaten *)
    let rec loop = function 
      | false -> return () 
      | true -> lwt _ = nextc i in loop (i.c <> u_qmark) in
    lwt _ = loop (i.c <> u_qmark) in
    lwt _ = nextc i in
    if i.c <> u_gt then 
      skip_pi i 
    else 
      nextc_eof i

  let rec skip_misc i ~allow_xmlpi = 
    match i.limit with          (* {Misc}* *)
      | Pi (p,l) when (str_empty p && str_eq n_xml (String.lowercase l)) -> 
	if allow_xmlpi then return () else err i (`Illegal_char_seq l)
      | Pi _ -> lwt _ = skip_pi i in lwt _ = p_limit i in skip_misc i ~allow_xmlpi
  | Comment -> lwt _ = skip_comment i in lwt _ =  p_limit i in skip_misc i ~allow_xmlpi
  | Text when is_white i.c -> 
      lwt _ = skip_white_eof i in lwt _ = p_limit i in skip_misc i ~allow_xmlpi
  | _ ->  return ()
      
  let p_chardata addc i =           (* {CharData}* ({Reference}{Chardata})* *)
      let rec loop = function 
	| false -> return ()
	| true -> 
	  lwt _ = 
	if i.c = u_amp then 
	  (lwt pr = p_reference i in String.iter (fun p -> return (addc i p)) pr)
	else if i.c = u_rbrack then 
	  begin 
	    addc i i.c;
	    lwt _ = nextc i in
	  if i.c = u_rbrack then begin 
	    addc i i.c;
	    lwt _ = nextc i in        (* detects ']'*']]>' *)
	    let rec loop = function 
	      | false -> return () 
	      | true -> addc i i.c ; lwt _ = nextc i in loop (i.c = u_rbrack) in 
            lwt _ = loop (i.c = u_rbrack) in
	    if i.c = u_gt then err i (`Illegal_char_seq (str "]]>"));
            return ()
	  end 
          else return () 
	end
      else
	(addc i i.c; nextc i) in loop (i.c <> u_lt)  
    in 
   loop (i.c <> u_lt) 

  let rec p_cdata addc i =                               (* {CData} {CDEnd} *)
    catch 
      (fun () -> 
	let rec loop () = 
	lwt _ = if i.c = u_rbrack then 
	    begin
	      lwt _ = nextc i in 

	    let rec loop = function 
	      | false -> return () 
	      | true -> lwt _ = nextc i in
	              if i.c = u_gt then 
			( lwt _ = nextc i in fail Exit)
		      else 
			( addc i u_rbrack ; loop (i.c = u_rbrack)) in

              lwt _ = loop (i.c = u_rbrack) in 
	      addc i u_rbrack; return () 
       
	  end else return () in 
	 addc i i.c;
	 lwt _ = nextc i in loop () in loop ())
      (fun e -> match e with Exit -> return () | _ as e -> fail e)
	  
  let p_xml_decl i ~ignore_enc ~ignore_utf16 =                (* {XMLDecl}? *)
    let yes_no = [v_yes; v_no] in
    let p_val i = lwt _ = skip_white i in lwt _ = accept i u_eq in lwt _ = skip_white i in p_attr_value i in
    let p_val_exp i exp = 
      lwt v = p_val i in 
      if not (List.exists (str_eq v) exp) then err_expected_seqs i exp v else return ()
    in
    match i.limit with
    | Pi (p, l) when (str_empty p && str_eq l n_xml) ->  
	lwt _ = skip_white i in 
        lwt v = p_ncname i in
	if not (str_eq v n_version) then err_expected_seqs i [ n_version ] v;
	lwt _ = p_val_exp i [v_version_1_0; v_version_1_1] in
	lwt _ = skip_white i in
	lwt _ = if i.c <> u_qmark then
	  begin
	    lwt n = p_ncname i in
	    lwt _ = if str_eq n n_encoding then 
	       begin
		 lwt v = p_val i in
		 let enc = String.lowercase v in
		 if not ignore_enc then
		   begin 
		     if str_eq enc v_utf_8 then i.uchar <- uchar_utf8 else
		       if str_eq enc v_utf_16be then i.uchar <- uchar_utf16be else
			 if str_eq enc v_utf_16le then i.uchar <- uchar_utf16le else
			   if str_eq enc v_iso_8859_1 then i.uchar <- uchar_iso_8859_1 else
			     if str_eq enc v_us_ascii then i.uchar <- uchar_ascii else
			       if str_eq enc v_ascii then i.uchar <- uchar_ascii else
				 if str_eq enc v_utf_16 then 
				   if ignore_utf16 then () else (err i `Malformed_char_stream)
                                             (* A BOM should have been found. *)
				 else
				   err i (`Unknown_encoding enc)
		   end ; 
		 lwt _ = skip_white i in
	         lwt _ = if i.c <> u_qmark then
		     begin 
	               lwt n = p_ncname i in 
	             if str_eq n n_standalone then p_val_exp i yes_no else err_expected_seqs i [ n_standalone; str "?>" ] n 
	             end else return () in
                 return ()
           end 
	  else 
            (if str_eq n n_standalone then
	       p_val_exp i yes_no
	    else
	      err_expected_seqs i [ n_encoding; n_standalone; str "?>" ] n) in return ()
	end else return () in
	lwt _ = skip_white i in
	lwt _ = accept i u_qmark in
	lwt _ = accept i u_gt in
	p_limit i
    | _ -> return ()

  let p_dtd_signal i = (* {Misc}* {doctypedecl} {Misc}* *)
    
    lwt _ = skip_misc i ~allow_xmlpi:false in
    
    if i.limit <> Dtd then
      return (`Dtd None)
    else
      begin
	let buf = addc_data i in
	let nest = ref 1 in                               
	clear_data i; 
	buf u_lt; buf u_emark;                             (* add eaten "<!" *)
	let rec loop () = 
	  match !nest > 0 with 
	    | false -> return () 
	    | true -> 
	      lwt _ = if i.c = u_lt then 
		begin 
		  lwt _ = nextc i in
		  if i.c <> u_emark then 
		    (buf u_lt; incr nest; return ()) 
		  else
		    begin 
		      lwt _ = nextc i in
		    if i.c <> u_minus then         (* Carefull with comments ! *) 
		      (buf u_lt; buf u_emark; incr nest; return ()) 
		    else
		      begin 
			lwt _ = nextc i in
		      if i.c <> u_minus then 
			(buf u_lt; buf u_emark; buf u_minus; incr nest; return ()) 
		      else                        
			(lwt _ = nextc i in skip_comment i)
                   end
	      end
	    end
	else 
           if i.c = u_quot or i.c = u_apos then
	  begin 
	    let c = i.c in
	    buf c; 
	    lwt _ = nextc i in
	  let rec loop = function
	    | false -> return ()
	    | true -> buf i.c ; lwt _ = nextc i in loop (i.c <> c) in
          lwt _ = loop (i.c <> c) in
	  buf c; 
           nextc i
	  end
	else 
          if i.c = u_gt then (buf u_gt; lwt _ = nextc i in decr nest; return ())
	else (buf i.c; nextc i)
      in loop () in 
      lwt _ = loop () in
      let dtd = Buffer.contents i.data in 
      lwt _ = p_limit i in
      lwt _ = skip_misc i ~allow_xmlpi:false in
      return (`Dtd (Some dtd));
    end
      	  
  let p_data i = 
    let rec bufferize addc i = 
      match i.limit with 
	| Text -> lwt _ = p_chardata addc i in lwt _ = p_limit i in bufferize addc i
	| Cdata -> lwt _ = p_cdata addc i in lwt _ = p_limit i in bufferize addc i
	| (Stag _ | Etag _) -> return ()
	| Pi _ -> lwt _ = skip_pi i in lwt _ = p_limit i in bufferize addc i
	| Comment -> lwt _ = skip_comment i in lwt _ =  p_limit i in bufferize addc i
	| Dtd -> err i (`Illegal_char_seq (str "<!D"))
	| Eoi -> err i `Unexpected_eoi
    in
    clear_data i;
    i.last_white <- true;
    lwt _ = bufferize (if i.stripping then addc_data_strip else addc_data) i in
    let d = Buffer.contents i.data in 
    return d
    
  let p_el_start_signal i n = 
    let expand_att (((prefix, local) as n, v) as att) = 
      if not (str_eq prefix String.empty) then expand_name i n, v else
      if str_eq local n_xmlns then (ns_xmlns, n_xmlns), v else
      att (* default namespaces do not influence attributes. *)
    in
    let strip = i.stripping in  (* save it here, p_attributes may change it. *) 
    lwt prefixes, atts = p_attributes i in
    
    i.scopes <- (n, prefixes, strip) :: i.scopes;
    return (`El_start ((expand_name i n), List.rev_map expand_att atts))

  let p_el_end_signal i n = 
    match i.scopes with
      | (n', prefixes, strip) :: scopes ->
	if i.c <> u_gt then err_expected_chars i [ u_gt ];
	if not (str_eq n n') then err_expected_seqs i [name_str n'] (name_str n); 
	i.scopes <- scopes;
	i.stripping <- strip;
	List.iter (Ht.remove i.ns) prefixes;
	let _ = if scopes = [] then (i.c <- u_end_doc; return ()) else (lwt _ = nextc i in p_limit i) in
	return `El_end
      | _ -> assert false
          
  let p_signal i = 
    if i.scopes = [] then 
      match i.limit with 
      | Stag n ->  p_el_start_signal i n
      | _ -> err i `Expected_root_element
    else 
      let rec find i : 'a Lwt.t =
	match i.limit with 
	  | Stag n -> p_el_start_signal i n
	  | Etag n -> p_el_end_signal i n
	  | Text | Cdata -> 
	    lwt d = p_data i in
	    if str_empty d then find i else return (`Data d)
	  | Pi _ -> lwt _ = skip_pi i in lwt _ =  p_limit i in find i
	  | Comment -> lwt _ = skip_comment i in lwt _ = p_limit i in find i
	  | Dtd -> err i (`Illegal_char_seq (str "<!D"))
	  | Eoi -> err i `Unexpected_eoi
      in
      lwt _ =
	match i.peek with          
	  | `El_start (n, _) ->                   (* finish to input start el. *)
	    lwt _ = skip_white i in
	  if i.c = u_gt then 
	    (lwt _ = accept i u_gt in p_limit i)
	  else
	    if i.c = u_slash then 
	      begin 
		let tag = match i.scopes with
		  | (tag, _, _) :: _ -> tag 
		  | _ -> assert false
		in
		(lwt _ = nextc i in i.limit <- Etag tag; return ()) 
	      end
	    else
	    err_expected_chars i [ u_slash; u_gt ]
      | _ -> return () in
      find i

  let eoi i = 
    catch
      (fun () ->
	if i.c = u_eoi then 
	  return true 
	else
	  if i.c <> u_start_doc then
	    return false
	  else                 (* In a document. *)
	    if i.peek <> `El_end then                (* Start of document sequence. *)
	      begin 
		lwt ignore_enc = find_encoding i in
	        lwt _ = p_limit i in
      
                lwt _ = p_xml_decl ~ignore_enc ~ignore_utf16:false i in 
	        lwt s = p_dtd_signal i in i.peek <- s ; return false
	    end
          else                                            (* Subsequent documents. *)
            begin 
	      
	    lwt _ = nextc_eof i in
	    lwt _ = p_limit i in 
         	if i.c = u_eoi then
		  return true
		else
		  begin 
		    lwt _ = skip_misc i ~allow_xmlpi:true in 
		    if i.c = u_eoi then
		      return true
		    else 
		      begin 
			lwt _ = p_xml_decl i ~ignore_enc:false ~ignore_utf16:true in
		      lwt s = p_dtd_signal i in 
		  i.peek <- s; 
		  return false
	  end
	end
      end )
      (fun e -> match e with 
	| Buffer.Full -> err i `Max_buffer_size
	| Malformed -> err i `Malformed_char_stream
	| End_of_file -> err i `Unexpected_eoi
	| _ as e -> fail e )

  let peek i = lwt e = eoi i in if e then err i `Unexpected_eoi else return i.peek

  let input i =
    catch
      (fun () -> 
	if i.c = u_end_doc then
  	( i.c <- u_start_doc; return i.peek) 
	else
	  begin

	    lwt s = peek i in

            lwt si = p_signal i in

            i.peek <- si ;
            return s 
          end)
    (fun e -> match e with 
      | Buffer.Full -> err i `Max_buffer_size
      | Malformed -> err i `Malformed_char_stream
      | End_of_file -> err i `Unexpected_eoi
      | e -> fail e)
  
let input_tree ~el ~data i = 
    lwt __input = input i in 
    match __input with
      | `Data d -> return (data d) 
      | `El_start tag -> 
	let rec aux i tags context =
	  lwt __input = input i in 
	  match __input with
	  | `El_start tag -> aux i (tag :: tags) ([] :: context)
	  | `El_end -> 
	    begin match tags, context with
	      | tag :: tags', childs :: context' ->
		let el = el tag (List.rev childs) in 
	      begin match context' with
	      | parent :: context'' -> aux i tags' ((el :: parent) :: context'')
	      | [] -> return el
	      end
	  | _ -> assert false
	  end
      | `Data d ->
	  begin match context with
	  | childs :: context' -> aux i tags (((data d) :: childs) :: context')
	  | [] -> assert false
	  end
      | `Dtd _ -> assert false
      in 
      aux i (tag :: []) ([] :: [])
  | _ -> invalid_arg err_input_tree


  let input_doc_tree ~el ~data i = 
    lwt __input = input i in 
  match __input with
    | `Dtd d -> lwt __tree = input_tree ~el ~data i in return (d, __tree)
  | _ -> invalid_arg err_input_doc_tree
    	
  let pos i = i.line, i.col

  (* Output *)

  type 'a frag = [ `El of tag * 'a list | `Data of string ]
  type dest = [ 
    | `Channel of Lwt_io.output_channel | `Buffer of std_buffer | `Fun of (int -> unit) ]

  type output = 
      { nl : bool;                (* True if a newline is output at the end. *)
	indent : int option;                        (* Optional indentation. *)
	fun_prefix : string -> string option;            (* Prefix callback. *)
        prefixes : string Ht.t;                   (* uri -> prefix bindings. *)
	outs : std_string -> int -> int -> unit Lwt.t;           (* String output. *)
	outc : char -> unit Lwt.t;                            (* character output. *)
	mutable last_el_start : bool;   (* True if last signal was `El_start *)
	mutable scopes : (name * (string list)) list;
                                       (* Qualified el. name and bound uris. *)
	mutable depth : int; }                               (* Scope depth. *) 

  let err_prefix uri = "unbound namespace (" ^ uri ^ ")"
  let err_dtd = "dtd signal not allowed here"
  let err_el_start = "start signal not allowed here"
  let err_el_end = "end signal without matching start signal"
  let err_data = "data signal not allowed here"

  let make_output ?(nl = false) ?(indent = None) ?(ns_prefix = fun _ ->None) d =
    let outs, outc = match d with 
    | `Channel c -> (Lwt_io.write_from_exactly c), (Lwt_io.write_char c)
    | `Buffer b -> (fun s p1 p2 -> Std_buffer.add_substring b s p1 p2 ; return ()), (fun s -> Std_buffer.add_char b s; return ())
    | `Fun f -> failwith "to be continued .. :)" 
	(* let os s p l = 
	  for i = p to p + l - 1 do f (Char.code (Std_string.get s p)) done 
	in
	let oc c = f (Char.code c) in 
	os, oc *)
    in
    let prefixes = 
      let h = Ht.create 10 in 
      Ht.add h String.empty String.empty;
      Ht.add h ns_xml n_xml;
      Ht.add h ns_xmlns n_xmlns;
      h
    in
    { outs = outs; outc = outc; nl = nl; indent = indent; last_el_start = false;
      prefixes = prefixes; scopes = []; depth = -1; fun_prefix = ns_prefix; }
 
  let outs o s = o.outs s 0 (Std_string.length s)

  let str_utf_8 s = String.to_utf_8 (fun _ s -> return s) "" s
  let out_utf_8 o s = lwt _ = String.to_utf_8 (fun o s -> lwt _ = outs o s in return o) o s in return ()

  let prefix_name o (ns, local) = 
    try 
      if str_eq ns ns_xmlns && str_eq local n_xmlns then
	return (String.empty, n_xmlns)
      else 
	return (Ht.find o.prefixes ns, local)
    with Not_found -> 
      match o.fun_prefix ns with
      | None -> lwt s = str_utf_8 ns in invalid_arg (err_prefix s)
      | Some prefix -> return (prefix, local)

  let bind_prefixes o atts = 
    let add acc ((ns, local), uri) = 
      if not (str_eq ns ns_xmlns) then acc else
      begin 
	let prefix = if str_eq local n_xmlns then String.empty else local in
	Ht.add o.prefixes uri prefix; 
	uri :: acc
      end
    in
    List.fold_left add [] atts

  let out_data o s =
    let out () s = 
      let len = Std_string.length s in
      let start = ref 0 in
      let last = ref 0 in
      let escape e = 
	lwt _ = o.outs s !start (!last - !start) in 
	lwt _ = outs o e in
	incr last;
        start := !last; 
        return () in
  let rec loop = function 
    | false -> return () 
    | true ->
      lwt _ = 
        match Std_string.get s !last with 
	  | '<' -> escape "&lt;"          (* Escape markup delimiters. *)
	  | '>' -> escape "&gt;"
	  | '&' -> escape "&amp;"
	  (* | '\'' -> escape "&apos;" *) (* Not needed we use \x22 for attributes. *)
	  | '\x22' -> escape "&quot;"
	  | _ -> incr last ; return () in loop (!last < len)
  in 
      lwt _ = loop (!last < len) in
      o.outs s !start (!last - !start)
    in
    String.to_utf_8 out () s
      
  let out_qname o (p, l) = 
    lwt _ = if not (str_empty p) then (lwt _ = out_utf_8 o p in o.outc ':') else return () in 
    out_utf_8 o l

  let out_attribute o (n, v) = 
    lwt _ = o.outc ' ' in 
    lwt __pn = prefix_name o n in
    lwt _ = out_qname o __pn in 
    lwt _ = outs o "=\x22" in
    lwt _ = out_data o v in 
    o.outc '\x22'
    
  let output o s = 
    let indent o = match o.indent with
    | None -> return () 
    | Some c -> let rec loop = function 
	| 0 -> return () 
	| n -> lwt _ = o.outc ' ' in loop (n-1) in loop (o.depth * c)  
    in
    let unindent o = match o.indent with None -> return () | Some _ -> o.outc '\n' in
    if o.depth = -1 then 
      begin match s with
      | `Dtd d ->
	  lwt _ = outs o "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" in
	  lwt _ = begin 
	    match d with 
	      | Some dtd -> lwt _ = out_utf_8 o dtd in o.outc '\n' 
	      | None -> return ()
	  end in
	  o.depth <- 0 ;
          return ()
      | `Data _ -> invalid_arg err_data
      | `El_start _ -> invalid_arg err_el_start
      | `El_end -> invalid_arg err_el_end
      end
    else
      begin match s with
      | `El_start (n, atts) -> 
	  lwt _ = if o.last_el_start then (lwt _ = outs o ">" in unindent o) else return () in
	  lwt _ = indent o in
	  let uris = bind_prefixes o atts in
	  lwt qn = prefix_name o n in
	  lwt _ = o.outc '<' in 
          lwt _ = out_qname o qn in 
          lwt _ = Lwt_list.iter_s (out_attribute o) atts in
	  o.scopes <- (qn, uris) :: o.scopes;
	  o.depth <- o.depth + 1;
	  o.last_el_start <- true ; 
	  return ()
      | `El_end -> 
	  begin 
	    match o.scopes with
	      | (n, uris) :: scopes' ->
		o.depth <- o.depth - 1;
		lwt _ = if o.last_el_start then
		  outs o "/>"
		else
		  begin 
		    lwt _ = indent o in
		    lwt _ = outs o "</" in 
	            lwt _ = out_qname o n in 
                    o.outc '>';
		  end in
		o.scopes <- scopes';
		List.iter (Ht.remove o.prefixes) uris;
		o.last_el_start <- false;
		if o.depth = 0 then
		  (lwt _ = if o.nl then o.outc '\n' else return () in  o.depth <- -1; return ()) 
		else unindent o
	  | [] -> invalid_arg err_el_end
	  end
      | `Data d -> 
	  lwt _ = if o.last_el_start then (lwt _ = outs o ">" in unindent o) else return () in
	  lwt _ = indent o in
	  lwt _ = out_data o d in
	  lwt _ = unindent o in
	  o.last_el_start <- false ; 
          return ()
      | `Dtd _ -> failwith err_dtd
      end

  let output_tree frag o v = 
    let rec aux o = function
      | (v :: rest) :: context ->
	  begin match frag v with
	  | `El (tag, childs) ->
	      lwt _ = output o (`El_start tag) in 
	      aux o (childs :: rest :: context)
	  | (`Data d) as signal -> 
	      lwt _ = output o signal in
	      aux o (rest :: context)
	  end
      | [] :: [] -> return ()
      | [] :: context -> lwt _ = output o `El_end in aux o context
      | [] -> assert false
    in
    aux o ([v] :: [])

  let output_doc_tree frag o (dtd, v) = 
    lwt _ = output o (`Dtd dtd) in 
    output_tree frag o v

end

(* Default streaming XML IO *)

module String = struct
  type t = string
  let empty = ""
  let length = String.length
  let append = ( ^ )
  let lowercase = String.lowercase
  let iter f s = 
    let len = Std_string.length s in
    let pos = ref ~-1 in
    let i () = 
      incr pos; 
      if !pos = len then fail Exit else 
      return (Char.code (Std_string.get s !pos))
    in
  
    catch 
      (fun () -> let rec loop () = 
		   lwt c = uchar_utf8 i in
		     f c ; loop () in
                     loop ())
      (fun e -> match e with Exit -> return () | _ as e -> fail e)

  let of_string s = s    
  let to_utf_8 f v x = f v x
  let compare = String.compare 
end
    
module Buffer = struct
  type string = String.t
  type t = Buffer.t
  exception Full 
  let create = Buffer.create
  let add_uchar b u =  
    try
      (* UTF-8 encodes an uchar in the buffer, assumes u is valid code point. *)
      let buf c = Buffer.add_char b (Char.chr c) in
      if u <= 0x007F then 
	(buf u)
      else if u <= 0x07FF then 
	(buf (0xC0 lor (u lsr 6)); 
	 buf (0x80 lor (u land 0x3F)))
      else if u <= 0xFFFF then
	(buf (0xE0 lor (u lsr 12));
	 buf (0x80 lor ((u lsr 6) land 0x3F));
       buf (0x80 lor (u land 0x3F)))
      else
	(buf (0xF0 lor (u lsr 18));
	 buf (0x80 lor ((u lsr 12) land 0x3F));
	 buf (0x80 lor ((u lsr 6) land 0x3F));
	 buf (0x80 lor (u land 0x3F)))
    with Failure _ -> raise Full
	  
  let clear b = Buffer.clear b
  let contents = Buffer.contents
  let length = Buffer.length
end

include Make(String) (Buffer)
    
(*----------------------------------------------------------------------------
  Copyright (c) 2007-2009, Daniel C. Bünzli
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:
        
  1. Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.

  2. Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the
     distribution.

  3. Neither the name of the Daniel C. Bünzli nor the names of
     contributors may be used to endorse or promote products derived
     from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  ----------------------------------------------------------------------------*)
