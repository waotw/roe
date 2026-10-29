# Deploy messages

What someone reads when a deploy can't start or fails, and what to do next.
One file per message; edit the wording in the file named after it.

- `_message.html.erb` is the box every message is drawn in. It styles plain
  `<p>`, `<ol>`, `<pre>` (a command to copy), `<code>` and `<a>`, so the
  message files need no classes. Restyle all of them there.
- Headings live in `app/services/deploy_messages.rb`, because the deploy log and
  the short error line use them too.
- A new message needs a file here and a heading there.

Each file gets these to work with:

| Local     | What it is                                                          |
|-----------|---------------------------------------------------------------------|
| `context` | `:settings` (Settings → Deploy), `:before` (stopped before starting), `:during` (failed partway) |
| `host`    | the deploy server, or `your-server.com`                             |
| `user`    | the SSH user, or `root`                                             |
| `ssh_key` | the deploy key, or `~/.ssh/your_deploy_key`                         |
| `target`  | `kamal` or `fly`                                                    |

Which message is shown is decided in Ruby: `DeployPreflight` before a deploy,
`DeployDiagnostics` (patterns in a failed log, and `messages_for`) after one,
and `DeployWatchdog` when Roe lost track of one. Anything unrecognised gets
`_unrecognised.html.erb`.
