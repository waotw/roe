// The site's own posts, pages, products and docs, for writing links to them.
// No CodeMirror here: the content editor (internal_links.js) and the plain
// metadata fields (field_links_controller.js) both use it.
//
// Links name files, not addresses (InternalLinks on the server):
//   [[posts/x]]  [[posts/x|text]]  [text](/posts/x.md)
// A file doesn't move when its title or url_name changes.

const LIST_URL = "/admin/internal_links";

// What the LINK button and ⌘K put between the brackets when nothing is
// selected (editor_controller#insertLink). Typing / in the () they leave
// opens the list, and picking a link replaces this with the title.
const PLACEHOLDER_TEXT = "link text";

let items = null;
let loading = null;
const byRef = new Map();
const byName = new Map();
const byAddress = new Map();
const listeners = new Set();

export function loaded() {
  return items !== null;
}

// Fetched once per page. Callers that draw links (red when they name
// nothing) redraw when it arrives.
export function load() {
  loading ||= fetch(LIST_URL, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    .then((r) => (r.ok ? r.json() : { items: [] }))
    .catch(() => ({ items: [] }))
    .then((json) => {
      items = (json.items || []).map(prepare);
      for (const fn of listeners) fn();
      return items;
    });
  return loading;
}

export function onLoad(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function prepare(item) {
  const name = item.ref.split("/").pop();
  const prepared = {
    ...item,
    name,
    path: `/${item.ref}`,
    hay: [item.title, `/${item.ref}`, item.url_name, item.address].join(" ").toLowerCase(),
  };
  byRef.set(item.ref, prepared);
  byAddress.set(item.address, prepared);
  if (!byName.has(name)) byName.set(name, []);
  byName.get(name).push(prepared);
  return prepared;
}

// What a link target names, as the server reads it: `posts/x`, `/posts/x.md`,
// `x` when only one file is called that, or an old-style address. undefined
// until the list has loaded; null when it names nothing.
export function resolve(target) {
  if (!items) return undefined;
  const raw = (target || "").trim().split("#")[0];
  const ref = raw.replace(/^\//, "").replace(/\.md$/i, "");
  if (ref.includes("/")) return byRef.get(ref) || byAddress.get(raw) || null;
  const named = byName.get(ref) || [];
  if (named.length === 1) return named[0];
  return byAddress.get(raw) || null;
}

// An address on this site that a page lives at — not media or other files.
export function internalUrl(url) {
  return (
    url.startsWith("/") &&
    !url.startsWith("//") &&
    !/^\/(media|system|theme|assets|rails)\//.test(url)
  );
}

export const WIKI = /\[\[([^[\]|\n]*)(\|[^[\]\n]*)?\]\]/g;

// The link target at `col` in one line of text, with offsets in that line:
//   { kind: "wiki" | "md", from, to, query, closed, current, text }
// `text` (Markdown links) is the [text] range, set when it's empty or the
// LINK button's placeholder, so picking fills in the title.
//
// Only where the link's target is written, never its text:
//   [[here|not here]]   [[here]]   [not here](here)
// While typing (`explicit` false), a Markdown link's target has to start
// with /: most links go to other sites, and `https:` mustn't open the list.
// On a click (or Ctrl-Space), the () must already hold an address on this
// site.
export function spotIn(line, col, explicit) {
  const before = line.slice(0, col);
  const after = line.slice(col);

  let m = before.match(/\[\[([^[\]|]*)$/);
  if (m) {
    const rest = after.match(/^[^[\]|]*/)[0];
    const tail = after.slice(rest.length);
    return {
      kind: "wiki",
      from: col - m[1].length,
      to: col + rest.length,
      query: m[1],
      closed: tail.startsWith("]]") || tail.startsWith("|"),
      current: m[1] + rest,
    };
  }

  // The address part, up to the caret. Spaces are allowed after the /, so
  // `/lab full` can narrow the list by two words; picking replaces them.
  m = before.match(/\]\(([^()\n]*)$/);
  if (m) {
    const rest = after.match(/^[^()\s]*/)[0];
    const url = m[1] + rest;
    if (explicit ? !internalUrl(url) : !m[1].startsWith("/")) return null;
    const close = before.length - m[0].length; // the ]
    const open = before.lastIndexOf("[", close);
    const label = open >= 0 ? before.slice(open + 1, close) : null;
    return {
      kind: "md",
      from: col - m[1].length,
      to: col + rest.length,
      query: m[1],
      closed: after.slice(rest.length).startsWith(")"),
      current: url,
      text: label === "" || label === PLACEHOLDER_TEXT ? { from: open + 1, to: close } : null,
    };
  }

  return null;
}

// Items matching what's typed, best first: the link's current target, then
// exact names, then titles and file names that start with it, then the most
// recently changed.
//
// The / that opens the list isn't part of the search: `/book` looks for
// "book", like `/ book`. A kind at the start narrows the list to it:
// `/posts`, `/posts/long`, `/posts long` (also pages, products,
// documentation, and docs for short). A page actually called that (say
// url_name `products`) still shows, first.
export function rank(query, current) {
  if (!items) return [];
  const typed = query.toLowerCase().replace(/\.md$/, "").trim();
  const bare = typed.replace(/^\/+/, "").trim();
  const kindMatch = bare.match(KIND_AT_START);
  const kind = kindMatch ? KINDS[kindMatch[1]] : null;
  const rest = kindMatch ? (kindMatch[2] || "").trim() : bare;
  const words = rest.split(/\s+/).filter(Boolean);

  const exact = (it) => it.ref === bare || it.name === bare || it.url_name === bare || it.address === typed;
  const score = (it) => {
    if (it === current) return -1;
    if (!bare) return 2;
    if (exact(it)) return 0;
    if (rest && (it.title.toLowerCase().startsWith(rest) || it.name.startsWith(rest))) return 1;
    return 2;
  };
  const matches = (it) => {
    if (it === current || (bare && exact(it))) return true;
    if (kind && kindOf(it) !== kind) return false;
    return words.every((w) => it.hay.includes(w));
  };
  return items
    .filter(matches)
    .map((it) => ({ it, s: score(it) }))
    .sort((a, b) => a.s - b.s || b.it.updated - a.it.updated)
    .slice(0, 100)
    .map(({ it }) => it);
}

const KINDS = { posts: "posts", pages: "pages", products: "products", documentation: "documentation", docs: "documentation" };
const KIND_AT_START = /^(posts|pages|products|documentation|docs)(?:(?:\/|\s+)(.*))?$/;

// posts, pages, products or documentation: the folder the file is in.
function kindOf(item) {
  return item.ref.split("/")[0];
}

// The second line of a list entry: the file, and the url_name when it differs.
export function detail(item) {
  return item.url_name && item.url_name !== item.name ? `${item.path} • ${item.url_name}` : item.path;
}

// The edits that point the link at `item`, in line offsets, and where the
// caret goes after: { changes: [{ from, to, insert }], caret }. `following`
// is the text after the spot's end (to step past a closing ]] or )).
export function edits(item, spot, following = "") {
  if (spot.kind === "wiki") {
    const insert = item.ref + (spot.closed ? "" : "]]");
    const past = spot.closed && following.startsWith("]]") ? 2 : 0;
    return { changes: [ { from: spot.from, to: spot.to, insert } ], caret: spot.from + insert.length + past };
  }

  const insert = `/${item.ref}.md${spot.closed ? "" : ")"}`;
  const changes = [];
  let shift = 0;
  if (spot.text) {
    const title = item.title.replace(/([[\]])/g, "\\$1");
    changes.push({ from: spot.text.from, to: spot.text.to, insert: title });
    shift = title.length - (spot.text.to - spot.text.from);
  }
  changes.push({ from: spot.from, to: spot.to, insert });
  return { changes, caret: spot.from + shift + insert.length + (spot.closed ? 1 : 0) };
}
