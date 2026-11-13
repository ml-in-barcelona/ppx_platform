  $ refmt --print ml ./input.re > input.ml

  $ ../standalone.exe -impl input.ml -cookie 'compilation-mode="melange"' | refmt --parse ml --print re
  let makeQuery = (~abortController, ~encoding=?, pathname, req, input) => {
    let signal =
      abortController->Option.map(abortController =>
        abortController->Fetch.AbortController.signal
      );
    let query = Js.Dict.empty();
    encoding->Option.forEach(enc =>
      query->Js.Dict.set("mode", "csv-" ++ EncodingT.unwrap(enc))
    );
    let defaultPostHeaders = (
      "Content-Type",
      "application/json; charset=utf-8",
    );
    switch (req.config.allowed_methods) {
    | GET_or_POST =>
      let queryParam = Sensitivity.to_query_param(req.config.sensitivity);
      let inputString = input->(req.writeInput)->Js.Json.stringify;
      let cloudflareLimit = 15000;
      let inputStringEncoded = inputString->Js.Global.encodeURIComponent;
      String.length(inputStringEncoded) > cloudflareLimit
        ? Fetch.fetchWithInit(
            Url.makeStringWithQueryDict(~pathname, ~query, ()),
            Fetch.RequestInit.make(
              ~method_=Post,
              ~body=inputString->Fetch.BodyInit.make,
              ~credentials=Include,
              ~headers=
                makeHeadersInit(
                  ~shouldBeGet=true,
                  ~initHeaders=defaultPostHeaders,
                  (),
                ),
              ~signal?,
              (),
            ),
          )
        : {
          Js.Dict.set(query, queryParam, inputStringEncoded);
          Fetch.fetchWithInit(
            Url.makeStringWithQueryDict(~pathname, ~query, ~encode=false, ()),
            Fetch.RequestInit.make(
              ~method_=Get,
              ~credentials=Include,
              ~headers=makeHeadersInit(),
              ~signal?,
              (),
            ),
          );
        };
    | POST_only =>
      Fetch.fetchWithInit(
        Url.makeStringWithQueryDict(~pathname, ~query, ()),
        Fetch.RequestInit.make(
          ~method_=Post,
          ~body=input->(req.writeInput)->Js.Json.stringify->Fetch.BodyInit.make,
          ~credentials=Include,
          ~headers=makeHeadersInit(~initHeaders=defaultPostHeaders, ()),
          ~signal?,
          (),
        ),
      )
    };
  };

  $ ../standalone.exe -impl input.ml | refmt --parse ml --print re
  [@warning "-27-32"]
  let [@alert
        melange_only(
          "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.",
        )
      ]
      makeQuery =
    [@alert "-melange_only"]
    (
      (~abortController, ~encoding=?, pathname, req, input) =>
        Ppx_platform.fail_melange_only("makeQuery")
    );
