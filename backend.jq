# R2 credentials from CLOUDFLARE_R2_*, as the cloudflare-sts action and
# `cloudflare-sts exec` set them, or an R2 API token's keys, in the AWS SDK's
# process credentials format.

# The environment variable $name's value, or an error if it's unset or empty.
def get_env($name):
  env[$name] // ""
  | if . == "" then error("\($name) is not set") else . end;

{
  Version: 1,
  AccessKeyId: get_env("CLOUDFLARE_R2_ACCESS_KEY_ID"),
  SecretAccessKey: get_env("CLOUDFLARE_R2_SECRET_ACCESS_KEY")
}
# Temporary credentials, like cloudflare-sts's, come with a session token;
# static keys, like an R2 API token's, don't.
+ if (env.CLOUDFLARE_R2_SESSION_TOKEN // "") != "" then
    {SessionToken: env.CLOUDFLARE_R2_SESSION_TOKEN}
  else
    {}
  end
