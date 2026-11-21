  $ cat > input.re << EOF
  > let make = () => {
  >   let%melange_only discard: Js.Promise.t(unit) => unit = value => ignore(value);
  >   ();
  > };
  > 
  > let%melange_only reifyStyle = (type a, x: 'a): (style(a), a) => {
  >     let isCanvasGradient = _ => false;
  >     let isCanvasPattern = _ => false;
  >     
  >     (
  >       if (Js.typeof(x) == "string") {
  >         Obj.magic(String);
  >       } else if (isCanvasGradient(x)) {
  >         Obj.magic(Gradient);
  >       } else if (isCanvasPattern(x)) {
  >         Obj.magic(Pattern);
  >       } else {
  >         invalid_arg("Unknown canvas style kind. Known values are: String, CanvasGradient, CanvasPattern");
  >       },
  >       Obj.magic(x),
  >     );
  >   };
  > 
  > EOF

  $ refmt --print ml input.re > input.ml

  $ ./standalone.exe -impl input.ml -js | refmt --parse ml --print re
  let make = () => {
    let discard: Js.Promise.t(unit) => unit = value => ignore(value);
    ();
  };
  let reifyStyle = (type a, x: 'a): (style(a), a) => {
    let isCanvasGradient = _ => false;
    let isCanvasPattern = _ => false;
    (
      if (Js.typeof(x) == "string") {
        Obj.magic(String);
      } else if (isCanvasGradient(x)) {
        Obj.magic(Gradient);
      } else if (isCanvasPattern(x)) {
        Obj.magic(Pattern);
      } else {
        invalid_arg(
          "Unknown canvas style kind. Known values are: String, CanvasGradient, CanvasPattern",
        );
      },
      Obj.magic(x),
    );
  };

  $ ./standalone.exe -impl input.ml | refmt --parse ml --print re
  let make = () => {
    [@alert "-melange_only"]
    let [@alert
          melange_only(
            "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.",
          )
        ]
        discard =
      value => {
        let _ = value;
        Ppx_platform.fail_melange_only("discard");
      };
    ();
  };
  [@warning "-32"]
  let [@alert
        melange_only(
          "This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.",
        )
      ]
      reifyStyle =
    [@alert "-melange_only"]
    (
      x => {
        let _ = x;
        Ppx_platform.fail_melange_only("reifyStyle");
      }
    );
