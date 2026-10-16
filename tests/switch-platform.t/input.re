switch%platform (Runtime.platform) {
| Native => doNativeLogic()
| Melange => doMelangeLogic()
};

let value =
  switch%platform (Runtime.platform) {
  | Native => doNativeLogic()
  | Melange => doMelangeLogic()
  };

let universal_fn = () => {
  switch%platform (Runtime.platform) {
  | Native => doNativeLogic()
  | Melange => doMelangeLogic()
  };
};

let universal_fn_with_arg1 = arg1 => {
  switch%platform (Runtime.platform) {
  | Native => doNativeLogic(arg1)
  | Melange => doMelangeLogic()
  };
};
