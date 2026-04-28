# Tooltips

Roe provides a reusable tooltip component for the admin interface to help users understand form fields, settings, and configuration options.

## Usage

Tooltips are rendered using the `shared/help_tooltip` partial:

```erb
<%= render 'shared/help_tooltip', text: "Short explanation." %>
```

### Basic Example

```erb
<label>
  Some Setting
  <%= render 'shared/help_tooltip',
             text: "Short plain-text explanation." %>
</label>
```

### With Title and HTML Content

```erb
<%= render 'shared/help_tooltip',
           title: "What is this?",
           text: ("<strong>Option A</strong> — description.<br>" \
                  "<strong>Option B</strong> — description.").html_safe %>
```

### Position Options

By default, tooltips appear below the triggering element. Use `position: "top"` when the field is near the bottom of a modal or viewport edge:

```erb
<%= render 'shared/help_tooltip', text: "...", position: "top" %>
```

## Real-World Example

From the admin configuration forms:

```erb
<% if @field_help&.key?(key) %>
  <%= render 'shared/help_tooltip',
             text: @field_help[key][:text],
             title: @field_help[key][:title] %>
<% end %>
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | String | Yes | Tooltip content (plain text or HTML) |
| `title` | String | No | Optional heading displayed above the text |
| `position` | String | No | `"top"` to show above, default shows below |

## Best Practices

- Keep tooltip text concise (1-2 sentences)
- Use HTML formatting sparingly (bold for emphasis, `<br>` for line breaks)
- Add titles only when the context isn't obvious from the label
- Use `position: "top"` when the tooltip would otherwise extend beyond the viewport
- Consider adding tooltips to all non-obvious configuration fields

## Related

- [Admin UI](./07-admin-ui.md) - Where tooltips are primarily used
- [Configuration](./06-configuration.md) - Common configuration fields that use tooltips
