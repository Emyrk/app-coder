# Home Assistant App: Coder

Runs the [Coder](https://coder.com) control plane (`coderd`) on Home Assistant.

- Workspaces are built only by external provisioner daemons. The app runs no
  built-in provisioners.
- Coder state is stored in an external PostgreSQL database.
- Users and provisioners reach Coder over Tailscale.

See the Documentation tab for setup steps.
