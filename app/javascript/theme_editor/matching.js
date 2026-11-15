// Which of a theme's rules style one element in the preview.
//
// A rule is tested by asking the element itself — element.matches(selector)
// — so the answer is the browser's, not a guess. Two kinds of selector need
// help first:
//
//   states       :hover, :focus, :active … only match while it's happening,
//                so they're taken out and the rule is labelled "on hover".
//   pseudo-elements  ::before, ::after, ::marker … style a part of the
//                element, not the element, so they're taken out too and the
//                rule is labelled "::before".
//
// Only top-level parts are removed: in `.a:not(:hover)` the :hover is part of
// a condition and stays.
//
// A rule inside @media or @supports counts as a match either way, but is
// marked inactive when the preview window doesn't meet the condition right
// now — the editor shows those dimmed, not hidden.

export const STATES = [
  "hover", "focus", "focus-visible", "focus-within", "active", "visited",
  "target", "focus-ring",
];

const PSEUDO_ELEMENTS = [
  "before", "after", "marker", "placeholder", "selection", "backdrop",
  "first-line", "first-letter", "file-selector-button", "cue",
];

// The labels a state reads as in the results.
const STATE_LABEL = {
  hover: "on hover",
  focus: "on focus",
  "focus-visible": "on keyboard focus",
  "focus-within": "while focus is inside",
  active: "while pressed",
  visited: "visited links",
  target: "when linked to",
};

// "a.b:hover::before" → { selector: "a.b", states: ["hover"], pseudo: "before" }
export function stripSelector(selector) {
  let out = "";
  const states = [];
  let pseudo = null;
  let depth = 0;
  let quote = null;
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (quote) {
      out += c;
      if (c === "\\") out += selector[++i] ?? "";
      else if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; out += c; continue; }
    if (c === "(" || c === "[") depth++;
    if (c === ")" || c === "]") depth--;
    if (c === ":" && depth === 0) {
      const double = selector[i + 1] === ":";
      const m = selector.slice(i + (double ? 2 : 1)).match(/^-?[\w-]+/);
      const name = m ? m[0].toLowerCase() : "";
      const isPseudoEl = double || PSEUDO_ELEMENTS.includes(name);
      const isState = !double && STATES.includes(name);
      if (isPseudoEl || isState) {
        let j = i + (double ? 2 : 1) + name.length;
        // ::part(x), ::slotted(x), ::highlight(x): skip their argument too.
        if (selector[j] === "(") {
          let d = 0;
          for (; j < selector.length; j++) {
            if (selector[j] === "(") d++;
            else if (selector[j] === ")" && --d === 0) { j++; break; }
          }
        }
        if (isPseudoEl) pseudo = name;
        else states.push(name);
        i = j - 1;
        continue;
      }
    }
    out += c;
  }
  out = out.trim();
  // ".a > :hover" leaves ".a >": the state stood for "any element".
  if (out === "" || /[>+~]\s*$/.test(out) || /\s$/.test(out)) out = (out + " *").trim();
  return { selector: out, states, pseudo };
}

export function labelFor({ states, pseudo }) {
  const parts = states.map((s) => STATE_LABEL[s] || `:${s}`);
  if (pseudo) parts.push(`::${pseudo}`);
  return parts.join(" · ");
}

function safeMatches(el, selector) {
  try {
    return el.matches(selector);
  } catch {
    return false;
  }
}

// Whether a rule's @media/@supports conditions hold in this window.
export function contextActive(context, win) {
  return context.every(({ kind, query }) => {
    try {
      if (kind === "media") return win.matchMedia(query).matches;
      if (kind === "supports") return win.CSS.supports(query.replace(/^\((.*)\)$/s, "$1")) || win.CSS.supports(query);
    } catch {
      return true;
    }
    return true;
  });
}

// The rules that style `el`, in file order:
//   [{ ruleIndex, selector, label, active }]
// A rule with several matching selectors is listed once, with the first.
export function matchRules(el, rules, win) {
  const results = [];
  rules.forEach((rule, ruleIndex) => {
    for (const sel of rule.selectors) {
      const stripped = stripSelector(sel.text);
      if (!safeMatches(el, stripped.selector)) continue;
      results.push({
        ruleIndex,
        selector: sel,
        label: labelFor(stripped),
        plain: !stripped.states.length && !stripped.pseudo,
        active: contextActive(rule.context, win),
      });
      break;
    }
  });
  return results;
}

// ── Other states ──────────────────────────────────────────────────────────
//
// A rule for the same element in a state it isn't in right now: the play
// button while playing, a <details> while open, a field while checked. Found
// by taking the conditions out of a selector — attribute tests and
// pseudo-classes, in every part of it, ancestors included — and asking
// whether what's left matches. What was taken out becomes the label:
// `when [data-playing="true"]`.
//
// Classes stay in, so a state written as a class (`.is-open`) isn't found
// this way; Roe's markup marks states with attributes.

// ".card-player[data-x] .t:not(.a)" →
//   { selector: ".card-player .t", removed: ["[data-x]", ":not(.a)"] }
export function relaxSelector(selector) {
  let out = "";
  const removed = [];
  for (let i = 0; i < selector.length; i++) {
    const c = selector[i];
    if (c === "[") {
      let j = i;
      let quote = null;
      for (; j < selector.length; j++) {
        const d = selector[j];
        if (quote) { if (d === "\\") j++; else if (d === quote) quote = null; }
        else if (d === '"' || d === "'") quote = d;
        else if (d === "]") break;
      }
      removed.push(selector.slice(i, j + 1));
      i = j;
      continue;
    }
    if (c === ":" && selector[i + 1] !== ":") {
      const m = selector.slice(i + 1).match(/^-?[\w-]+/);
      let j = i + 1 + (m ? m[0].length : 0);
      if (selector[j] === "(") {
        let d = 0;
        for (; j < selector.length; j++) {
          if (selector[j] === "(") d++;
          else if (selector[j] === ")" && --d === 0) { j++; break; }
        }
      }
      removed.push(selector.slice(i, j));
      i = j - 1;
      continue;
    }
    out += c;
  }
  // A part left with nothing (".a > :checked" → ".a > ") means "any element".
  const tokens = out.replace(/\s*([>+~])\s*/g, " $1 ").trim().split(/\s+/).filter(Boolean);
  const parts = [];
  for (const t of tokens) {
    const combinator = /^[>+~]$/.test(t);
    if (combinator && (!parts.length || /^[>+~]$/.test(parts[parts.length - 1]))) parts.push("*");
    parts.push(t);
  }
  if (!parts.length || /^[>+~]$/.test(parts[parts.length - 1])) parts.push("*");
  return { selector: parts.join(" "), removed };
}

// The pseudo-classes that are a state an element moves in and out of. Not
// :has(), :empty or :first-child: those describe where it is, not a state,
// and listing them would put every paragraph's :has(.site-logo) rule under
// every paragraph.
const STATE_PSEUDOS = new Set([
  "checked", "disabled", "enabled", "open", "closed", "invalid", "valid",
  "user-invalid", "user-valid", "required", "optional", "placeholder-shown",
  "indeterminate", "default", "read-only", "read-write", "popover-open",
  "modal", "fullscreen", "playing", "paused", "autofill",
]);

// "[data-playing]", ":checked", ":not(.is-enhanced)", ":not([hidden])"
export function isStateCondition(part) {
  if (part.startsWith("[")) return true;
  const m = part.match(/^:([\w-]+)(?:\((.*)\))?$/s);
  if (!m) return false;
  if (m[1] === "not" && m[2] !== undefined) {
    return m[2].split(",").every((x) => /^\s*(\.[\w-]+|\[[^\]]+\]|:[\w-]+)\s*$/.test(x) &&
      (!x.trim().startsWith(":") || STATE_PSEUDOS.has(x.trim().slice(1))));
  }
  return m[2] === undefined && STATE_PSEUDOS.has(m[1]);
}

// Rules that would style `el` in another state, in file order:
//   [{ ruleIndex, selector, label, state: true, active }]
// `skip` is the set of rule indexes already listed as matching.
export function otherStateRules(el, rules, win, skip = new Set()) {
  const results = [];
  rules.forEach((rule, ruleIndex) => {
    if (skip.has(ruleIndex)) return;
    for (const sel of rule.selectors) {
      const stripped = stripSelector(sel.text);
      // Only rules that name the element itself: the last part must have a
      // class, an id or a tag. Otherwise `:checked` alone would match
      // everything once taken out.
      const last = stripped.selector.split(/\s*[>+~\s]\s*/).pop();
      if (!/[.#]|^[a-z]/i.test(relaxSelector(last).selector)) continue;
      const { selector, removed } = relaxSelector(stripped.selector);
      if (!removed.length || !removed.every(isStateCondition) || !safeMatches(el, selector)) continue;
      const label = ["when " + removed.join(""), labelFor(stripped)].filter(Boolean).join(" · ");
      results.push({ ruleIndex, selector: sel, label, state: true, plain: false, active: contextActive(rule.context, win) });
      break;
    }
  });
  return results;
}

// Properties a child takes from its parent unless it sets its own.
export const INHERITED = new Set([
  "color", "font", "font-family", "font-size", "font-style", "font-variant",
  "font-weight", "font-stretch", "font-feature-settings", "font-variation-settings",
  "line-height", "letter-spacing", "word-spacing", "text-align", "text-indent",
  "text-transform", "text-shadow", "white-space", "word-break", "overflow-wrap",
  "hyphens", "visibility", "cursor", "list-style", "list-style-type",
  "list-style-position", "list-style-image", "direction", "quotes", "tab-size",
  "-webkit-font-smoothing", "caret-color", "accent-color", "color-scheme",
]);

// What `el` inherits, nearest ancestor first: for each ancestor that sets an
// inherited property the element (or a nearer ancestor) doesn't, the
// declarations it passes down.
//   [{ element, ruleIndex, decls: [decl] }]
export function inheritedRules(el, rules, win) {
  const taken = new Set();
  const own = matchRules(el, rules, win).filter((r) => r.plain && r.active);
  for (const r of own) for (const d of rules[r.ruleIndex].decls) taken.add(d.prop);

  const out = [];
  for (let a = el.parentElement; a; a = a.parentElement) {
    const found = matchRules(a, rules, win).filter((r) => r.plain && r.active);
    // Later rules win, so read the ancestor's rules from the last one back.
    const here = [];
    for (const r of [...found].reverse()) {
      const decls = rules[r.ruleIndex].decls.filter((d) => INHERITED.has(d.prop) && !taken.has(d.prop));
      decls.forEach((d) => taken.add(d.prop));
      if (decls.length) here.unshift({ element: a, ruleIndex: r.ruleIndex, decls });
    }
    out.push(...here);
  }
  return out;
}

// "div.card-player.is-enhanced" for the breadcrumb.
export function describe(el) {
  const tag = el.tagName.toLowerCase();
  const id = el.id ? `#${el.id}` : "";
  const classes = [...el.classList].filter((c) => !c.startsWith("te-")).slice(0, 3).map((c) => `.${c}`).join("");
  return `${tag}${id}${classes}`;
}
