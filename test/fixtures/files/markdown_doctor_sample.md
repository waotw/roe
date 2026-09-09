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

## 5. Fence indented into a code block — NEEDS ATTENTION

Four spaces or more and kramdown reads the line as an indented code block
instead of a fence, so the backticks are printed rather than obeyed. The same
four spaces under a list item or a footnote would be a continuation, and fine.

    ```ruby
    puts "the fence above is content, not a fence"
    ```

## 6. Code fence escaping a list — NEEDS ATTENTION

A fence at column zero between two list items leaves the list, exactly as an
unindented blockquote does. The list carries on afterwards, which is what makes
it a mistake rather than a code block that simply follows a list.

- shopping list item one

```ruby
puts "this block was meant to belong to item one"
```

- shopping list item two

## 7. Footnote continuation that misses — FIXABLE

A footnote's second paragraph has to reach four spaces. Two is aiming for it and
missing, and the paragraph quietly leaves the note.

Referencing the short note[^short] so it isn't reported as unused as well.

[^short]: The first paragraph of this note is fine.

  This second paragraph is indented two spaces, so it isn't part of the note.

## 8. List indented too little to nest — NEEDS ATTENTION

An ordered item's text starts at column three, so a child indented two looks
nested and isn't — it renders as a flat, renumbered sibling.

1. first item
  1. this was meant to be nested under the first item
2. second item

## 9. Single backtick alone on a line

A lone backtick isn't a fence — three or more are needed.

`

## 10. Two-backtick fence

Two backticks look like a fence but aren't one.

``
this was meant to be a code block
``

## 11. Fence with five backticks

Roe supports three or four, not five.

`````
too many backticks to be a valid fence
`````

## 12. Four-backtick fence with nothing nested inside

Four backticks exist so a fence can contain another fence. With nothing nested,
three would have been right.

````text
just some plain text, no inner fence in sight
````

## 13. Nested fence using the same length as its wrapper

An outer fence has to be longer than the one it contains, or the first inner
closer ends the outer block early.

```outer
```inner
```

## 14. Mismatched closing fence

Opened with three backticks, closed with four.

```ruby
puts "the closer below doesn't match"
````

## 15. Unclosed fence

Last on purpose: everything after an unclosed fence is swallowed into it, so any
further sections would go unchecked.

```ruby
puts "this fence is never closed"
