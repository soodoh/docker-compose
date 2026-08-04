# Omada export, TLS, and adoption

The controller certificate is self-signed for the DNS name `Omada`. CI therefore stores the authenticated controller certificate as the protected `OMADA_CA_PEM` secret, maps `Omada` to the Tailscale address of `docker-host` on the ephemeral runner, and keeps provider TLS verification enabled. Do not replace this with `skip_tls_verify = true`.

Capture the certificate over an already authenticated SSH connection and verify its fingerprint out of band. With a dedicated read-only plan account, export the adopted LAN and its reservations without changing controller configuration:

```sh
OMADA_URL=https://Omada:8043 \
OMADA_USERNAME='<protected>' \
OMADA_PASSWORD='<protected>' \
OMADA_SITE='<site-name>' \
  scripts/export-omada-state.py \
    --connect-host 192.168.0.100 \
    --ca-file .local/omada/controller-ca.pem \
    --output .local/omada/export.json
```

Review the ignored JSON and place its exact contents in the protected `OMADA_EXPORT_JSON` environment secret. Adoption uses tracked dynamic import blocks for `<site>/<network-id>` and `<site>/<MAC>` identities. Run `scripts/reconcile-infrastructure plan --phase adoption`; the policy permits imports but not ordinary updates. Apply that exact adoption plan only after every proposed action is an import/no-op.

After import, exercise the provider only with its dedicated qualification reservation on an explicitly disposable address. Remove it through a second reviewed plan, record three consecutive no-op plans, set `omada.provider_qualified` and `OMADA_ADOPTION_COMPLETE`, and then leave adoption mode disabled.