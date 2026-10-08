# terraform-cloudflare-backend

[![CI](https://github.com/tf-contrib/terraform-cloudflare-backend/actions/workflows/ci.yml/badge.svg)](https://github.com/tf-contrib/terraform-cloudflare-backend/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tf-contrib/terraform-cloudflare-backend?include_prereleases)](https://github.com/tf-contrib/terraform-cloudflare-backend/releases)
[![License](https://img.shields.io/badge/License-MPL--2.0-brightgreen.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-compatible-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org)

[Cloudflare R2](https://developers.cloudflare.com/r2/) as an
[OpenTofu](https://opentofu.org) and Terraform state backend, with its
credentials from the environment and no secret on disk.

R2 speaks the S3 API, so the `s3` backend works with it. That backend reads
its credentials from an AWS shared config profile. `terraform-cloudflare-backend`
is that profile's `credential_process`: it prints `CLOUDFLARE_R2_ACCESS_KEY_ID`,
`CLOUDFLARE_R2_SECRET_ACCESS_KEY` and, for temporary ones,
`CLOUDFLARE_R2_SESSION_TOKEN`, in the format the backend reads. Whatever sets
them:

- **In CI,** the [cloudflare-sts action](https://github.com/cf-contrib/cloudflare-sts),
  with short-lived credentials for the job.
- **Locally,** `cloudflare-sts exec -- tofu ...`, with short-lived credentials
  from your login.
- **Or** an R2 API token's keys, exported, when there's no broker to ask.

Without them it fails at once, saying so: it never fetches credentials itself.
`AWS_*` is neither read nor set. The Cloudflare provider needs nothing from it:
it reads `CLOUDFLARE_API_TOKEN`, which the action and `cloudflare-sts exec` set
too, so the same command gets both.

## Usage

Add the package to the repo's dev shell:

```nix
{
  inputs.terraform-cloudflare-backend.url = "github:tf-contrib/terraform-cloudflare-backend/v0.2.0"; # x-release-please-version

  # ...
  devShells.default = pkgs.mkShell {
    packages = [
      pkgs.opentofu
      terraform-cloudflare-backend.packages.${system}.default
    ];
  };
}
```

Or install it for yourself: `nix profile install github:tf-contrib/terraform-cloudflare-backend`.

Then write `backend.ini` beside the root module:

```ini
[profile tofu]
credential_process = terraform-cloudflare-backend
```

And point the backend at it:

```hcl
terraform {
  backend "s3" {
    endpoints                   = { s3 = "https://<account-id>.r2.cloudflarestorage.com" }
    bucket                      = "example-org-tofu-state"
    key                         = "github.com/example-org/app/terraform.tfstate"
    region                      = "auto"
    profile                     = "tofu"
    shared_config_files         = ["backend.ini"]
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
```

### With cloudflare-sts

A [cloudflare-sts](https://github.com/cf-contrib/cloudflare-sts) profile with a
`bucket`, limited to the prefix the backend's `key` is under, gives the job or
the person the R2 credentials:

```yaml
  - name: example-org/app:tofu
    provider: com.github.actions
    claims:
      - repository: example-org/app
    token:
      # ... what the Cloudflare provider needs
    bucket:
      name: example-org-tofu-state
      permission: object-read-write
      prefixes: ["github.com/{repository}/"]
```

See [Buckets](https://github.com/cf-contrib/cloudflare-sts/tree/main/crates/cloudflare-sts-api#buckets)
for the rules on prefixes, and why IDs make better ones than names.

In CI:

```yaml
permissions:
  id-token: write

steps:
  - uses: actions/checkout@v7
  - uses: DeterminateSystems/nix-installer-action@v23
  - uses: cf-contrib/cloudflare-sts@v0.21.0
    with:
      url: https://cloudflare-sts-api.example.com
      profile: example-org/app:tofu
  - run: nix develop --command tofu init -input=false
  - run: nix develop --command tofu plan -input=false
```

Locally, every `tofu` command that reads or writes state runs under
`cloudflare-sts exec`, which gives the backend and the provider their
credentials alike, and revokes the token when `tofu` exits:

```sh
cloudflare-sts login --url https://cloudflare-sts-api.example.com   # once
cloudflare-sts exec --profile example-org/app:tofu -- tofu init
cloudflare-sts exec --profile example-org/app:tofu -- tofu plan
```

`CLOUDFLARE_STS_CLI_URL` and `CLOUDFLARE_STS_CLI_PROFILE`, e.g. set in the dev
shell, save the options.

## Limits

- **No expiry.** `cloudflare-sts exec` doesn't pass the credentials' expiry on,
  so OpenTofu uses them for the whole run. An apply that outlasts the profile's
  `ttl` fails to write its state at the end. OpenTofu then saves it to
  `errored.tfstate`. Give the profile a `ttl` longer than your longest apply.
- **No options.** Which credentials, and for how long, is up to what sets
  them. An option, such as an older `backend.ini`'s `--profile`, is refused
  rather than ignored.

## Development

```sh
nix develop
bash tests/run.sh          # the script in this repo
nix flake check            # shellcheck, and the tests against the package
```

## License

[MPL-2.0](LICENSE)
