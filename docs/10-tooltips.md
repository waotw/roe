Example from codebase:

```erb
<% if @field_help&.key?(key) %>
                              <%= render 'shared/help_tooltip',
                                         text: @field_help[key][:text],
                                         title: @field_help[key][:title] %>
                            <% end %>
```

Tool tips are rendered like this:

```
<%= render 'shared/help_tooltip', text: "Short explanation." %>
<%= render 'shared/help_tooltip', text: "...".html_safe, title: "Type" %>
<%= render 'shared/help_tooltip', text: "...", position: "top" %>
```

Wherever you render a form field label, drop this in:

```erb
<label>
  Some Setting
  <%= render 'shared/help_tooltip',
             text: "Short plain-text explanation." %>
</label>
```

With a title and formatting:

```erb
<%= render 'shared/help_tooltip',
           title: "What is this?",
           text: ("<strong>Option A</strong> — description.<br>" \
                  "<strong>Option B</strong> — description.").html_safe %>
```

Position above the label if the field is near the bottom of a modal, etc.:

```erb
<%= render 'shared/help_tooltip', text: "...", position: "top" %>
```
