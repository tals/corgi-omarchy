// src/locale.ts
//! Locale negotiation shared by the CLI and browser-safe viewer code.
//! The Omarchy panel runs this in Qt's QML engine (tools/omarchy_motion.ts):
//! no BigInt literals or `Intl`, and builtins Qt lacks only through
//! the Omarchy plugin's qml_shims.js.
var locales = ["en", "zh", "ja", "ko", "ru"];
var translated = ["zh", "ja", "ko", "ru"];
var names = {
  en: "English",
  zh: "简体中文",
  ja: "日本語",
  ko: "한국어",
  ru: "Русский"
};
function parse(value) {
  const language = value.trim().toLowerCase().replaceAll("_", "-").split(/[.@]/)[0].split("-")[0];
  switch (language) {
    case "en":
    case "zh":
    case "ja":
    case "ko":
    case "ru":
      return language;
    case "c":
    case "posix":
      return "en";
    default:
      return null;
  }
}
function detect(env, preference, system = []) {
  var _a, _b, _c, _d;
  const override = (_a = env.CORGI_LANG) === null || _a === undefined ? undefined : _a.trim();
  if (override && override.toLowerCase() !== "auto")
    return (_b = parse(override)) !== null && _b !== undefined ? _b : "en";
  if (preference)
    return preference;
  const messages = env.LC_ALL || env.LC_MESSAGES || env.LANG;
  if (messages && /^(?:C|POSIX)(?:[.@].*)?$/i.test(messages))
    return "en";
  for (const language of ((_c = env.LANGUAGE) !== null && _c !== undefined ? _c : "").split(":")) {
    const parsed = parse(language);
    if (parsed)
      return parsed;
  }
  if (messages)
    return (_d = parse(messages)) !== null && _d !== undefined ? _d : "en";
  for (const language of system) {
    const parsed = parse(language);
    if (parsed)
      return parsed;
  }
  return "en";
}
var plurals = new Map;
function plural(language, count) {
  let rules = plurals.get(language);
  if (!rules)
    plurals.set(language, rules = new Intl.PluralRules(language));
  return rules.select(count);
}
export {
  detect,
  locales,
  names,
  parse,
  plural,
  translated
};
