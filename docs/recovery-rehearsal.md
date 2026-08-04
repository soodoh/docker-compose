# Recovery rehearsal

Run the non-mutating static rehearsal from a clean controller:

```sh
scripts/rehearse-recovery --static
```

It validates the contract/provider locks, exercises hostile archive and volume fixtures, and syntax-checks the recovery playbooks. A pass proves only static control flow.

A live qualification must use an isolated Proxmox host and disposable recovery targets. It must demonstrate exact backup selection and checksum binding, safe extraction, fresh-volume inventory, activation, service health, decrypted-staging cleanup, cold boot, and a post-recovery no-op. Measure elapsed time and save only secret-free hashes and outcomes.

Never call an unrehearsed production restore a rehearsal. This repository intentionally has no command that silently escalates `--static` into a live restore.