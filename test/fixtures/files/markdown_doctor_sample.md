---
title: "Markdown Doctor — Every Issue"
subtitle: "A deliberately broken post for testing the warnings panel"
date: "2026-08-17T09:00Z"
post_type: "article"
status: "draft"
author: "Benjamin Welch"
tags: []
url_name: "markdown-doctor-test"
excerpt: "Every problem the markdown doctor can find, one per section, so the editor's warnings panel can be seen doing its job."
audience: "everyone"
published_to: "site"
---
This post is broken on purpose. Every section below trips one of the doctor's
checks, so the warnings panel should list them all.

Keep it as `status: draft` — it isn't meant to be published, only opened in the
editor. A pristine copy lives at `current/test/fixtures/files/markdown_doctor_sample.md`;
copy it back over this file to start again after pressing Fix All.

**Section order matters.** The list checks come first because a fence problem
leaves the scanner believing it's inside a code block, which suppresses every
list check below it. Rearranging the sections will change what gets reported.

## 1. List item with no blank line above it — FIXABLE

This paragraph runs straight into a list with no blank line between them.
Kramdown copes, so this one is about tidiness rather than broken output.
- first item
- second item

## 2. Blockquote escaping a list — FIXABLE

A `>` at column zero between two list items breaks out of the list. Indenting it
four spaces keeps it inside the item.

- shopping list item one
> this quote is meant to belong to item one
- shopping list item two

## 3. Heading swallowed by the list above — FIXABLE

A heading written straight after a list item, with no blank line between them,
ends up *inside* that item instead of ending the list.

- first item
- second item
## This heading is trapped in the bullet above

## 4. Footnote problems — NEEDS ATTENTION

Footnotes fail quietly. A reference with no definition prints as raw text[^99],
and a definition nobody references renders nothing at all, so a note that was
written simply isn't there.

[^unused]: This note is never referenced, so it won't appear in the post.

[^dupe]: First definition of this one.

Referencing the duplicate[^dupe] here so only its second definition is at fault.

[^dupe]: Second definition — kramdown keeps this one and drops the first.

## 5. Single backtick alone on a line

A lone backtick isn't a fence — three or more are needed.

`

## 6. Two-backtick fence

Two backticks look like a fence but aren't one.

``
this was meant to be a code block
``

## 7. Fence with five backticks

Roe supports three or four, not five.

`````
too many backticks to be a valid fence
`````

## 8. Four-backtick fence with nothing nested inside

Four backticks exist so a fence can contain another fence. With nothing nested,
three would have been right.

````text
just some plain text, no inner fence in sight
````

## 9. Nested fence using the same length as its wrapper

An outer fence has to be longer than the one it contains, or the first inner
closer ends the outer block early.

```outer
```inner
```

## 10. Mismatched closing fence

Opened with three backticks, closed with four.

```ruby
puts "the closer below doesn't match"
````

## 11. Unclosed fence

Last on purpose: everything after an unclosed fence is swallowed into it, so any
further sections would go unchecked.

```ruby
puts "this fence is never closed"
