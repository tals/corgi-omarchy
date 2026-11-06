// qml_shims.js
//! What Corgi's modules use and Qt's QML engine lacks. motion.ts imports this
//! first, so it runs before them. Plain JavaScript that Qt runs as it is.
//! Add a shim when Corgi's code starts using a builtin the engine doesn't have.
function define(target, name, value) {
  if (!target[name])
    Object.defineProperty(target, name, { value, writable: true, configurable: true, enumerable: false });
}
define(Object, "fromEntries", function(entries) {
  const out = {};
  for (const [key, value] of entries)
    out[key] = value;
  return out;
});
define(Object, "hasOwn", function(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
});
define(String.prototype, "replaceAll", function(find, replace) {
  if (typeof find !== "string")
    return this.replace(find, replace);
  const text = String(this);
  let out = "", from = 0, at;
  while ((at = text.indexOf(find, from)) !== -1) {
    out += text.slice(from, at) + (typeof replace === "function" ? replace(find, at, text) : replace);
    from = at + find.length;
    if (!find) {
      if (at >= text.length)
        return out;
      out += text[at];
      from = at + 1;
    }
  }
  return out + text.slice(from);
});
define(Array.prototype, "flatMap", function(f) {
  return [].concat(...this.map(f));
});
