  $ cat > input.re << EOF
  > let%melange_only valueFromEvent = evt => React.Event.Form.target(evt)##value;
  > let%melange_only getSortedWordCountsBrowserOnly = (words: array(string)): array((string, int)) => {
  >   words->List.map->Js.log;
  > };
  > 
  > let%melange_only renderToElementWithId = (~id="", component) => {
  >   switch (ReactDOM.querySelector("#" ++ id)) {
  >     | Some(node) =>
  >       let root = ReactDOM.Client.createRoot(node);
  >       ReactDOM.Client.render(root, component);
  >     | None => Js.Console.error("RR.renderToElementWithId : no element of id '" ++ id ++ "' found in the HTML.")
  >     };
  >   };
  > 
  > let%melange_only getSortedWordCountsBrowserOnly = (words: array(string)): array((string, int)) => {
  >   words |> Js.log |> List.map;
  > };
  > 
  > let%melange_only getSortedWordCountsBrowserOnly = (words: array(string)): array((string, int)) => {
  >   words
  >   ->Js.Array2.reduce(
  >     (acc, word) => {
  >       Map.String.update(acc, word, count =>
  >         switch (count) {
  >         | Some(existingCount) => Some(existingCount + 1)
  >         | None => Some(1)
  >         }
  >       )
  >     },
  >     Map.String.empty
  >   )
  >   ->Map.String.toArray
  >   ->Js.Array2.sortInPlaceWith(((_, a), (_, b)) => b - a);
  > };
  > 
  > EOF

  $ refmt --print ml input.re > input.ml

  $ ./standalone.exe -impl input.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let valueFromEvent evt = (React.Event.Form.target evt)##value
  
  let getSortedWordCountsBrowserOnly (words : string array) =
    (words |. List.map |. Js.log : (string * int) array)
  
  let renderToElementWithId ?(id = "") =
   fun component ->
    match ReactDOM.querySelector ("#" ^ id) with
    | ((Some node) [@explicit_arity]) ->
        let root = ReactDOM.Client.createRoot node in
        ReactDOM.Client.render root component
    | None ->
        Js.Console.error
          ("RR.renderToElementWithId : no element of id '" ^ id
         ^ "' found in the HTML.")
  
  let getSortedWordCountsBrowserOnly (words : string array) =
    (words |> Js.log |> List.map : (string * int) array)
  
  let getSortedWordCountsBrowserOnly (words : string array) =
    (((words |. Js.Array2.reduce)
        (fun acc ->
          fun word ->
           Map.String.update acc word (fun count ->
               match count with
               | ((Some existingCount) [@explicit_arity]) ->
                   Some (existingCount + 1) [@explicit_arity]
               | None -> Some 1 [@explicit_arity]))
        Map.String.empty
     |. Map.String.toArray |. Js.Array2.sortInPlaceWith) (fun (_, a) ->
         fun (_, b) -> b - a)
      : (string * int) array)

  $ ./standalone.exe -impl input.ml | ocamlformat - --enable-outside-detected-project --impl
  let (valueFromEvent
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun evt ->
    Ppx_platform.fail_melange_only "valueFromEvent")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (getSortedWordCountsBrowserOnly
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun words ->
    Ppx_platform.fail_melange_only "getSortedWordCountsBrowserOnly")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (renderToElementWithId
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ?id component ->
    Ppx_platform.fail_melange_only "renderToElementWithId")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (getSortedWordCountsBrowserOnly
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun words ->
    Ppx_platform.fail_melange_only "getSortedWordCountsBrowserOnly")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (getSortedWordCountsBrowserOnly
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun words ->
    Ppx_platform.fail_melange_only "getSortedWordCountsBrowserOnly")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
