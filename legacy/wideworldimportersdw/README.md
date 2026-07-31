# WideWorldImportersDW (Standard) — vendored bacpac

This directory holds the Microsoft sample data warehouse `WideWorldImportersDW`
in `.bacpac` form so the demo is fully self-contained (no Microsoft download
required at demo time).

## Source

- Official Microsoft sample: **WideWorldImportersDW-Standard.bacpac**
- Origin: https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers (released under the MIT license).
- Approximate size: 21 MB (well under GitHub's 100 MB single-file limit).

## Reproducibility

If you need to refresh the bacpac (e.g. it has drifted from upstream), run:

```bash
./refresh_bacpac.sh
```

That script downloads the bacpac from the Microsoft SQL Server samples release
on GitHub and verifies the SHA-256. The committed copy is the source of truth
for the demo; the download is only for maintainers.

## Import

`infra/azure/bootstrap.sh` calls `SqlPackage /a:Import` against this bacpac to
load the Azure SQL free-offer database. See
[infra/azure/bootstrap.sh](../../infra/azure/bootstrap.sh) for the exact
invocation.

## License

The WideWorldImporters sample is released by Microsoft under the MIT License.
See [../../LICENSE](../../LICENSE) for the repo's license (also MIT).
