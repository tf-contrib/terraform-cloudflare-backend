# Changelog

## [0.2.0](https://github.com/tf-contrib/terraform-cloudflare-backend/compare/v0.1.0...v0.2.0) (2026-10-08)


### ⚠ BREAKING CHANGES

* the program is terraform-cloudflare-backend (was terraform-cloudflare-sts), from github:tf-contrib/terraform-cloudflare-backend. It takes no options: --profile, --url and --ttl are refused, so backend.ini's credential_process is `terraform-cloudflare-backend`, and state commands run under `cloudflare-sts exec --`.

### Features

* rename to terraform-cloudflare-backend, credentials from the environment only ([e148b70](https://github.com/tf-contrib/terraform-cloudflare-backend/commit/e148b70bb45896479245a331d952117890f2c322))

## 0.1.0 (2026-10-08)


### Features

* terraform-cloudflare-sts, R2 credentials for the s3 backend from cloudflare-sts ([0880099](https://github.com/tf-contrib/terraform-cloudflare-sts/commit/0880099986e5cf16606da2e4c44d3345fbcd9c48))
