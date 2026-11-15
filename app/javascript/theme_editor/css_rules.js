// Reads a theme's CSS — the text in the editor, saved or not — into the
// pieces the theme editor works with: its rules, its section headings and
// where each variable is set.
//
// Every position is an offset into the text, so a result can be shown in the
// editor exactly where it is. Nothing here touches the page or the editor;
// it imports only the CSS parser, so it can be tested in Node.

import { parser } from "@lezer/css";

// A section and a subsection heading, one line each (see ThemeSections in
// app/services/theme_sections.rb, which reads the same format).
const SECTION = /^\/\* ==== (.+?) ====(?: \*\/)?\s*$/;
const SUBSECTION = /^\/\* ---- (.+?) ---- \*\/\s*$/;

// [{ level: 1|2, name, from, line }]
export function parseSections(text) {
  const out = [];
  let from = 0;
  const lines = text.split("\n");
  lines.forEach((line, i) => {
    let m;
    if ((m = line.match(SECTION))) out.push({ level: 1, name: m[1], from, line: i + 1 });
    else if ((m = line.match(SUBSECTION))) out.push({ level: 2, name: m[1], from, line: i + 1 });
    from += line.length + 1;
  });
  return out;
}

// Splits a selector list at its top-level commas, keeping each part's
// offset. Commas inside :is(), :not(), :has() or [attr="a,b"] stay put.
export function splitSelectors(text, offset = 0) {
  const parts = [];
  let depth = 0;
  let quote = null;
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = null;
    } else if (c === '"' || c === "'") quote = c;
    else if (c === "(" || c === "[") depth++;
    else if (c === ")" || c === "]") depth--;
    else if (c === "," && depth === 0) {
      parts.push([start, i]);
      start = i + 1;
    }
  }
  parts.push([start, text.length]);
  return parts
    .map(([a, b]) => {
      const raw = text.slice(a, b);
      const lead = raw.length - raw.trimStart().length;
      const t = raw.trim().replace(/\s+/g, " ");
      return { text: t, from: offset + a + lead, to: offset + a + lead + raw.trim().length };
    })
    .filter((s) => s.text);
}

// The at-rule a rule sits inside: { kind: "media"|"supports"|…, query }.
function contextOf(node, text) {
  const out = [];
  for (let p = node.parent; p; p = p.parent) {
    if (p.name === "MediaStatement" || p.name === "SupportsStatement" || p.name === "AtRule") {
      const block = p.getChild("Block");
      const head = text.slice(p.from, block ? block.from : p.to).trim();
      const m = head.match(/^@([\w-]+)\s*(.*)$/s);
      if (m) out.unshift({ kind: m[1], query: m[2].trim().replace(/\s+/g, " "), from: p.from });
    }
  }
  return out;
}

function declarationsOf(block, text) {
  const decls = [];
  for (let c = block.firstChild; c; c = c.nextSibling) {
    if (c.name !== "Declaration") continue;
    const name = c.firstChild;
    if (!name) continue;
    const prop = text.slice(name.from, name.to).trim();
    const colon = text.indexOf(":", name.to);
    let value = text.slice(colon + 1, c.to).trim();
    const important = /!\s*important\s*$/i.test(value);
    value = value.replace(/!\s*important\s*$/i, "").trim();
    decls.push({ prop: prop.toLowerCase().startsWith("--") ? prop : prop.toLowerCase(), value, important, from: c.from, to: c.to });
  }
  return decls;
}

// Every style rule in the text, in file order:
//   { selectorText, selectors: [{ text, from, to }], from, to,
//     context: [{ kind, query }], decls: [{ prop, value, important, from, to }] }
// Rules inside @keyframes and @font-face aren't rules an element can match,
// so they're left out.
export function parseRules(text) {
  const tree = parser.parse(text);
  const rules = [];
  tree.iterate({
    enter(ref) {
      if (ref.name === "KeyframesStatement") return false;
      if (ref.name !== "RuleSet") return;
      const node = ref.node;
      const block = node.getChild("Block");
      if (!block) return false;
      const selectorText = text.slice(node.from, block.from);
      rules.push({
        selectorText: selectorText.trim().replace(/\s+/g, " "),
        selectors: splitSelectors(selectorText, node.from),
        from: node.from,
        to: node.to,
        context: contextOf(node, text),
        decls: declarationsOf(block, text),
      });
      return false;
    },
  });
  return rules;
}

// Where each custom property is set: name → [{ from, ruleIndex, selectorText }],
// with a :root setting first, since that's the one a theme means to change.
export function variableDefinitions(rules) {
  const defs = new Map();
  rules.forEach((rule, ruleIndex) => {
    for (const d of rule.decls) {
      if (!d.prop.startsWith("--")) continue;
      if (!defs.has(d.prop)) defs.set(d.prop, []);
      defs.get(d.prop).push({ from: d.from, ruleIndex, selectorText: rule.selectorText, context: rule.context });
    }
  });
  for (const list of defs.values()) {
    list.sort((a, b) => rank(a) - rank(b) || a.from - b.from);
  }
  return defs;
}

function rank(def) {
  const root = /(^|,)\s*(:root|html)\s*(,|$)/.test(def.selectorText);
  return (root ? 0 : 2) + (def.context.length ? 1 : 0);
}

// The variables a value uses: "calc(var(--a) + var(--b, 1px))" → ["--a", "--b"]
export function variablesIn(value) {
  return [...value.matchAll(/var\(\s*(--[\w-]+)/g)].map((m) => m[1]);
}

// The widths at which a theme's layout changes, from its @media
// (min-width / max-width) queries in px, widest first:
//   [{ width, rules }]
// A min-width of 601px is shown at 601 (the first width it applies at), a
// max-width of 600px at 600 (the last). `queries` is how many @media blocks
// use that width.
export function breakpoints(text) {
  const counts = new Map();
  const re = /@media[^{]*?\((min|max)-width:\s*(\d+(?:\.\d+)?)px\)[^{]*\{/g;
  let m;
  while ((m = re.exec(text))) {
    const width = Math.round(parseFloat(m[2]));
    counts.set(width, (counts.get(width) || 0) + 1);
  }
  return [...counts.entries()]
    .map(([width, queries]) => ({ width, queries }))
    .sort((a, b) => b.width - a.width);
}

// The section a position falls in: the last heading at or before it.
export function sectionAt(sections, pos) {
  let section = null;
  let sub = null;
  for (const s of sections) {
    if (s.from > pos) break;
    if (s.level === 1) {
      section = s;
      sub = null;
    } else sub = s;
  }
  return { section, sub };
}
