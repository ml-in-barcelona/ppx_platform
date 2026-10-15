let%browser_only click_handler (event : int) = event + 1
let target = match%platform () with Server -> "native" | Client -> "js"

include struct
  let only_js = "js"
end [@@platform js]

include struct
  let only_native = "native"
end [@@platform native]
