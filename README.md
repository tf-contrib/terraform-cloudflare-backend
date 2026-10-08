# terraform-cloudflare-sts

[![CI](https://github.com/tf-contrib/terraform-cloudflare-sts/actions/workflows/ci.yml/badge.svg)](https://github.com/tf-contrib/terraform-cloudflare-sts/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/tf-contrib/terraform-cloudflare-sts?include_prereleases)](https://github.com/tf-contrib/terraform-cloudflare-sts/releases)
[![License](https://img.shields.io/badge/License-MPL--2.0-brightgreen.svg)](LICENSE)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-compatible-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org)

[Cloudflare R2](https://developers.cloudflare.com/r2/) as an
[OpenTofu](https://opentofu.org) and Terraform state backend, with short-lived
credentials from [cloudflare-sts](https://github.com/cf-contrib/cloudflare-sts)
and no secret on disk or in CI.

R2 speaks the S3 API, so the `s3` backend works with it. That backend reads
its credentials from an AWS shared config profile. `terraform-cloudflare-sts`
is that profile's `credential_process`:

- **In CI,** the [cloudflare-sts action](https://github.com/cf-contrib/cloudflare-sts)
  has already set `CLOUDFLARE_R2_*`. It prints those.
- **Under `cloudflare-sts exec -- tofu ...`,** the CLI has set them too. It
  prints those.
- **Otherwise,** it runs `cloudflare-sts exec` to get them, with your stored
  login, and prints what it gets. So `tofu init` or `tofu state list` works
  without wrapping.

`AWS_*` is neither read nor set. The Cloudflare provider needs nothing from
it: it reads `CLOUDFLARE_API_TOKEN`, which the action and `cloudflare-sts exec`
set.

## Usage

Add the package to the repo's dev shell:

```nix
{
  inputs.terraform-cloudflare-sts.url = "github:tf-contrib/terraform-cloudflare-sts/v0.0.0"; # x-release-please-version

  # ...
  devShells.default = pkgs.mkShell {
    packages = [
      pkgs.opentofu
      terraform-cloudflare-sts.packages.${system}.default
    ];
  };
}
```

Or install it for yourself: `nix profile install github:tf-contrib/terraform-cloudflare-sts`.

Then write `backend.ini` beside the root module:

```ini
[profile tofu]
credential_process = terraform-cloudflare-sts --profile example-org/app:tofu
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

The options after `terraform-cloudflare-sts` are `cloudflare-sts exec`'s:
`--profile`, `--url` and `--ttl`. They apply only when it runs
`cloudflare-sts exec` itself. With `CLOUDFLARE_R2_*` already set, they're
ignored: the action's `profile` decides. `CLOUDFLARE_STS_CLI_URL` and
`CLOUDFLARE_STS_CLI_PROFILE` work too, e.g. set in the dev shell.

### The broker's profile

The `--profile` is a cloudflare-sts profile with a `bucket`, limited to the
prefix the backend's `key` is under:

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

### In CI

```yaml
permissions:
  id-token: write

steps:
  - uses: actions/checkout@v7
  - uses: DeterminateSystems/nix-installer-action@v23
  - uses: cf-contrib/cloudflare-sts@v0.20.0
    with:
      url: https://cloudflare-sts-api.example.com
      profile: example-org/app:tofu
  - run: nix develop --command tofu init -input=false
  - run: nix develop --command tofu plan -input=false
```

### Locally

```sh
cloudflare-sts login --url https://cloudflare-sts-api.example.com   # once
cloudflare-sts exec --profile example-org/app:tofu -- tofu plan      # backend and provider
tofu state list                                                      # backend only
```

## Limits

- **No expiry.** `cloudflare-sts exec` doesn't pass the credentials' expiry
  on, so OpenTofu uses them for the whole run. An apply that outlasts the
  profile's `ttl` fails to write its state at the end. OpenTofu then saves it
  to `errored.tfstate`. Give the profile a `ttl` longer than your longest
  apply.
- **No sign-in prompt.** OpenTofu runs `credential_process` without a
  terminal, so a missing or expired login fails. Run `cloudflare-sts login`,
  then try again.
- **One mint per run.** Each `tofu` command that runs it gets new R2
  credentials. If the profile also has a `token`, the token is minted and
  revoked with them. The R2 credentials can't be revoked, and expire.

## Development

```sh
nix develop
bash tests/run.sh          # the script in this repo, against a fake cloudflare-sts
nix flake check            # shellcheck, and the tests against the package
```

## License

[MPL-2.0](LICENSE)
