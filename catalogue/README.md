# Remote model catalogue

`models.json` is fetched **at runtime by shipped apps** from:

```
https://raw.githubusercontent.com/Zman2087/PintSizeAI/main/catalogue/models.json
```

(see `lib/features/models/remote_catalogue_service.dart`). Treat it as a
published API:

- **Never move or rename this file** — installed apps break silently.
- Keep `schemaVersion` stable; entries must parse via `ModelVariant.fromJson`.
- Remote entries override bundled catalogue entries by `id`, so a bad edit
  here changes what users download. Only `https://` URLs are honoured.
- Verify `fileSizeBytes` against the Hugging Face API
  (`/api/models/{repo}/tree/main`) — the in-app fit checker relies on it.
