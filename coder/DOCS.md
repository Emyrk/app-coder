# Coder

This app runs the Coder control plane (`coderd`). It is built for one setup:

- **No built-in provisioners.** `CODER_PROVISIONER_DAEMONS` is fixed to `0`.
  Workspace builds run only on external provisioner daemons, which is a Coder
  Premium feature, so you need a license.
- **External PostgreSQL.** The app does not run a database. You give it a
  connection URL.
- **Tailscale for access.** Users and external provisioners reach Coder through
  the Tailscale app.

## 1. Set up PostgreSQL

Any PostgreSQL server that Coder supports works. These steps use the
[TimescaleDB app](https://github.com/expaso/hassos-addon-timescaledb), which
serves several databases from one server.

1. Add the `https://github.com/expaso/hassos-addons` repository and install
   the **TimescaleDB** app.
1. In its configuration, add `coder` to `databases`. Do not add it to
   `timescale_enabled`.
1. Start the app and change the default `postgres` superuser password.
1. Create a role for Coder and give it the database:

   ```sql
   CREATE ROLE coder LOGIN PASSWORD '<strong password>';
   ALTER DATABASE coder OWNER TO coder;
   ```

1. Copy the hostname from the TimescaleDB app's **Info** page. Your connection
   URL is:

   ```text
   postgres://coder:<password>@<hostname>:5432/coder?sslmode=disable
   ```

## 2. Set up Tailscale

1. Install the [Tailscale app](https://github.com/hassio-addons/app-tailscale)
   and log in.
1. In the Tailscale admin console:
   - On the **DNS** page, turn on MagicDNS and HTTPS certificates.
   - On the **Services** page, define a service named `svc:coder`.
1. Configure the Tailscale app to publish Coder:

   ```yaml
   advertise_tags:
     - tag:homeassistant
   services:
     - name: svc:coder
       target: http://127.0.0.1:3000
       protocol: https
       port: 443
   ```

1. Restart the Tailscale app, then approve this device as the host of
   `svc:coder` on the **Services** page.

Coder is now reachable at `https://coder.<tailnet>.ts.net` from devices on your
tailnet.

## 3. Configure this app

| Option              | Required | Description |
|---------------------|----------|-------------|
| `access_url`        | Yes      | The Tailscale URL from step 2, for example `https://coder.<tailnet>.ts.net`. |
| `pg_connection_url` | Yes      | The connection URL from step 1. |
| `license`           | No       | Your Coder Premium license JWT. |
| `admin_email`       | No       | Creates the first owner user on a new deployment. Also used to add the license. |
| `admin_username`    | No       | Defaults to the part of `admin_email` before the `@`. |
| `admin_password`    | No       | Password for the admin user. |
| `env_vars`          | No       | Extra `CODER_*` server settings, as `name` and `value` pairs. |

On start, after Coder is healthy, the app:

1. Creates the first owner user from `admin_email`, `admin_username`, and
   `admin_password`, if the deployment has no users yet.
1. Logs in as that user and adds `license`. The app remembers which license it
   added and skips this step until the license changes.

If you leave the admin options empty, create the first user in the dashboard
and add the license under **Deployment** > **Licenses**.

The app always sets these values, and `env_vars` cannot override them:
`CODER_ACCESS_URL`, `CODER_PG_CONNECTION_URL`, `CODER_HTTP_ADDRESS`,
`CODER_PROVISIONER_DAEMONS`, `CODER_CACHE_DIRECTORY`, and `CODER_CONFIG_DIR`.

## 4. Connect external provisioners

On a machine in your tailnet with the `coder` CLI and the tools your templates
need (for example Docker or Terraform providers):

```shell
# Once, as an owner: create a key.
coder login https://coder.<tailnet>.ts.net
coder provisioner keys create home

# On the provisioner machine.
export CODER_URL=https://coder.<tailnet>.ts.net
export CODER_PROVISIONER_DAEMON_KEY=<key>
coder provisioner start
```

Provisioners only open outbound connections to Coder.

## Limits

- **No subdomain workspace apps.** Tailscale service names do not support
  wildcards, so `CODER_WILDCARD_ACCESS_URL` is not set. Workspace apps use
  path-based URLs.
- **Tailnet only.** Tailscale Services do not support Funnel, so Coder is not
  reachable from the public internet.
- **Workspaces must reach the access URL.** Workspace agents connect to
  `access_url`, so the hosts that run workspaces must also be on the tailnet.

## Data and backups

Coder state lives in PostgreSQL, so back up the database app. This app keeps
only a cache and CLI config in `/data`. The cache is left out of Home Assistant
backups.
