# WideWorldImportersDW (Standard) — bacpac

Microsoft sample data warehouse `WideWorldImportersDW` in `.bacpac` form.

## Source

- Official sample: **WideWorldImportersDW-Standard.bacpac** (~22 MB)
- Origin: https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers (MIT)
- Release asset: `wide-world-importers-v1.0`

## Vendored + verified

The bacpac is **committed in this repo** so demos work offline. Integrity is
enforced by `download_bacpac.sh`:

```bash
EXPECTED_SHA256=96e9b87dfe3665aefde12a2c4decb835982803470d7f224b988d8f512db2a6c5
./download_bacpac.sh   # no-op if present and hash matches; else re-downloads
```

## Import

`infra/azure/bootstrap.sh` runs `SqlPackage /a:Import` against this bacpac.
Azure SQL free offer does **not** support `.bak` restore — bacpac is required.

## License

WideWorldImporters is MIT (Microsoft). This repo is also MIT — see
[../../LICENSE](../../LICENSE).
