# WideWorldImportersDW (Standard) — vendored bacpac

This directory holds the Microsoft sample data warehouse `WideWorldImportersDW`
in `.bacpac` form so the demo is fully self-contained (no Microsoft download
required at demo time).

## Source

- Official Microsoft sample: **WideWorldImportersDW-Standard.bacpac**
- Origin: https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers (released under the MIT license).
- Approximate size: 21 MB (well under GitHub's 100 MB single-file limit).

## Reproducibility

The bacpac is **downloaded on first use** (not committed as a binary). Run:

```bash
./import_azure_sql.sh
```

That downloads from the Microsoft SQL Server samples release on GitHub and
prints the SHA-256. Pin `EXPECTED_SHA256` in the script after the first
successful download. SqlPackage import is performed by
`infra/azure/bootstrap.sh`.

## Import

`infra/azure/bootstrap.sh` calls `SqlPackage /a:Import` against this bacpac to
load the Azure SQL free-offer database. See
[infra/azure/bootstrap.sh](../../infra/azure/bootstrap.sh) for the exact
invocation.

## License

The WideWorldImporters sample is released by Microsoft under the MIT License.
See [../../LICENSE](../../LICENSE) for the repo's license (also MIT).
