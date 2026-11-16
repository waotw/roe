Headings, paragraphs, lists, quotes, code, tables and footnotes: every text element a theme styles.

## Heading 2

A paragraph with [a link](#heading-2), **bold text**, *italic text*, ***bold italic***, `inline code`, ~~struck through~~ and ==highlighted== words, followed by a footnote.[^1] Line length, line height and the space between paragraphs come from the theme.

A second paragraph, so the gap between two paragraphs shows. It runs long enough to wrap onto a few lines at most widths, which is what most of a site's text looks like.

### Heading 3

Text under a third-level heading.

#### Heading 4

Text under a fourth-level heading.

##### Heading 5

Text under a fifth-level heading.

###### Heading 6

Text under a sixth-level heading.

## Lists

- An unordered list item
- A second item with a longer line that wraps onto the next line, to show the hanging indent
  - A nested item
  - Another nested item
- A third item

1. An ordered list item
2. A second item
   1. A nested ordered item
3. A third item

## Quotes

> A blockquote. It can run over several lines, and it can hold more than one paragraph.
>
> This is its second paragraph.
>
> — Attribution, written as plain text

```card
type: pullquote
text: A pull quote in the centre of the text, with an attribution.
attribution: Sample Author
position: center
```

```card
type: pullquote
text: A pull quote floated to the left.
position: left
```

The paragraphs beside a floated pull quote wrap around it. This one is long enough to show how the text flows next to the quote and then returns to the full width of the column once it has passed it. Themes set the quote's width and the gap around it.

```card
type: pullquote
text: A pull quote floated to the right.
position: right
```

The same again on the other side. Text wraps to the left of the quote and then carries on underneath it at the full width, so the space between the quote and the text is easy to compare with the left-hand one above.

## Code

Inline code looks like `SiteConfig.get("theme.active")` inside a sentence.

```ruby
class Greeting
  def initialize(name)
    @name = name
  end

  def to_s
    "Hello, #{@name}!"
  end
end
```

```
A code block with no language, and a line that is long enough to need scrolling or wrapping at narrow widths, depending on the theme.
```

## Poetry

```poetry
So much depends
upon

  a red wheel
  barrow

glazed with rain
water
```

## Tables

| Episode | Title | Length |
|:--|:--|--:|
| 1 | Starting Out | 24:10 |
| 2 | The Long Way Round | 31:45 |
| 3 | Listening Back | 28:02 |

## Horizontal rule

Above the rule.

---

Below the rule.

## Footnotes

A sentence with a second footnote.[^2] The notes themselves are at the bottom of the page.

[^1]: The first footnote. It can hold *formatting* and [links](#footnotes).
[^2]: The second footnote.
