# Conventional Commits — Quick Cheatsheet

A lightweight convention for writing commit messages that humans can read and machines can parse.

---

## The Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

---

## Types

| Type       | Use When...                                         | SemVer |
|------------|-----------------------------------------------------|--------|
| `feat`     | You add a new feature                               | MINOR  |
| `fix`      | You fix a bug                                       | PATCH  |
| `docs`     | You change documentation only                       | —      |
| `style`    | You fix formatting, whitespace, semicolons, etc.  | —      |
| `refactor` | You refactor code without changing behavior         | —      |
| `perf`     | You improve performance                             | —      |
| `test`     | You add or fix tests                                | —      |
| `chore`    | You update build tasks, deps, config, etc.          | —      |
| `build`    | You change the build system or external deps        | —      |
| `ci`       | You change CI configuration files or scripts        | —      |

---

## Scope (optional)

A noun describing the part of the codebase affected:

```
feat(parser): add ability to parse arrays
fix(auth): correct login redirect logic
docs(api): update endpoint examples
```

---

## Breaking Changes

Two ways to mark them:

**Option 1:** Append `!` to the type/scope

```
feat(api)!: remove deprecated v1 endpoints
fix!: drop support for Node 14
```

**Option 2:** Add a `BREAKING CHANGE` footer

```
feat: change default config format

BREAKING CHANGE: config files must now use YAML instead of JSON
```

Both can be used together. Any breaking change bumps **MAJOR**.

---

## Examples

**Simple fix:**
```
fix: resolve draft import filtering for Substack CSV
```

**Feature with scope:**
```
feat(importer): add live data fetcher for podcast episodes
```

**With body:**
```
refactor: extract truthy? helper for boolean parsing

Use ActiveModel::Type::Boolean so we handle "1", "true",
"TRUE" consistently. Fixes draft filtering bug.
```

**With footer:**
```
fix: correct date parsing for empty post_date fields

Closes: #42
```

---

## Rules

1. **Type** is required and lowercase (`feat`, `fix`, etc.)
2. **Scope** is optional, in parentheses, no spaces (`feat(api):`)
3. **Description** is required, starts lowercase, no period
4. **Body** is optional, separated by one blank line
5. **Footers** are optional, use `Token: value` format
6. **Breaking changes** use `!` in the prefix OR `BREAKING CHANGE:` footer
7. Everything is case-insensitive except `BREAKING CHANGE` (must be uppercase)

---

## Simple Workflow

1. **Before committing, ask:** "What type of change is this?"
2. **Write the subject line:** `type(scope): description`
3. **If it's a breaking change:** add `!` after the scope
4. **If it needs context:** add a body explaining the "why"
5. **If it closes an issue:** add `Closes: #123` footer
6. **Commit it:** `git commit -m "feat: add draft support to importer"`

---

## Why Use This?

- Auto-generate CHANGELOGs
- Auto-determine SemVer bumps (PATCH/MINOR/MAJOR)
- Better code review and history
- Easier to automate releases
- Clearer for teammates and future you

---

## Reference

Full specification: https://www.conventionalcommits.org/en/v1.0.0/
