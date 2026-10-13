# Notifications

> **Retired.** HFIM-client is replaced by `hfim run --on <server>` from hfim-core
> (phase R-4). Its scripts print the hfim command that replaces them and exit 2.
> Set up a Server and run a campaign there: hfim-docs, `guides/run-on-a-server.md`.
> The table of every old command and its replacement is in that guide.

Get a Telegram message when a background campaign finishes, with a summary and
the results CSV attached. Entirely optional; if you do not configure it,
campaigns run silently.

## 1. Create a bot

- Open Telegram and message `@BotFather`.
- Send `/newbot`, then pick a name and a username (e.g. `my_fim_bot`).
- BotFather replies with a token like `123456:ABC-xyz`. Save it.

## 2. Get your chat ID

- Search for your new bot in Telegram and send it any message (e.g. "hello").
- Then run, with your token substituted in:

  ```bash
  curl -s https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates \
    | python3 -m json.tool | grep '"id"' | head -1
  ```

- The number it prints is your chat ID.

## 3. Add both to config.yaml

```yaml
telegram_bot_token: "123456:ABC-xyz"
telegram_chat_id: "987654321"
```

That is all. `run.sh` syncs these to the server, and any
[background campaign](background-jobs.md) sends you a summary plus the results
CSV when it completes. The credentials stay in your local `config.yaml` (which
is git-ignored).

## See also

- [Background Jobs](background-jobs.md) - notifications fire on background runs
- [Setup](setup.md) - where `config.yaml` lives
