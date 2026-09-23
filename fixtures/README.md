# Fixtures

Golden Cryptomator format-8 vault shared with the macOS sibling.

`PASSWORD` and `vault/` are **gitignored** (same policy as [guillebot/cryptomako](https://github.com/guillebot/cryptomako)). Copy them from the macOS clone:

```bash
cp -R ../cryptomako/fixtures/PASSWORD ../cryptomako/fixtures/vault fixtures/
```

Tree inside the unlocked vault (see `expected-ls.txt`):

```
hello.txt
notes/todo.md
bin/tiny.png
café résumé.txt
nnn…180….txt     # forces .c9s shortening
```

In the iOS app: Storage → **Local fixtures**, path = absolute path to `fixtures/vault`, password from `PASSWORD`.
