type node

external owner_document : node -> node = "ownerDocument" [@@mel.get] [@@melange_only]
external set_attribute : node -> name:string -> string -> unit = "setAttribute" [@@mel.send] [@@melange_only]

let%melange_only set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]
