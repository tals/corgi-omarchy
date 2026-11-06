// src/i18n.ts
import * as locale from "./locale.mjs";
import * as generated from "./i18n.generated.mjs";
var _a;
//! Ordinary template tags; catalogs contain generated native template functions.
//! The Omarchy panel runs this in Qt's QML engine (tools/omarchy_motion.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.
var locales2 = locale.locales;
var names2 = locale.names;
var current = locale.detect(typeof process === "undefined" ? {} : (_a = process.env) !== null && _a !== undefined ? _a : {});
var keys = new WeakMap;
function language() {
  return current;
}
function setLanguage(language) {
  current = language;
}
function document(source) {
  var _a, _b, _c;
  return current === "en" ? source : (_c = (_b = (_a = generated.messages[current])[JSON.stringify([source])]) === null || _b === undefined ? undefined : _b.call(_a)) !== null && _c !== undefined ? _c : source;
}
function t(strings, ...values) {
  if (current !== "en") {
    let key = keys.get(strings);
    if (key === undefined) {
      key = JSON.stringify(strings);
      keys.set(strings, key);
    }
    const message = generated.messages[current][key];
    if (message)
      return message(...values);
  }
  return String.raw({ raw: strings }, ...values);
}
export {
  document,
  language,
  locales2 as locales,
  names2 as names,
  setLanguage,
  t
};
