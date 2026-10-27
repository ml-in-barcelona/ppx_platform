let%melange_only click_handler (event : int) = event + 1
let target = match%platform () with Native -> "native" | Melange -> "js"

include struct
  let only_js = "js"
end [@@melange_only]

include struct
  let only_native = "native"
end [@@native_only]

let cookie_mode = [%compilation_mode]
