# Shared OpenTofu modules

Roots intentionally remain separate by failure domain. Add a module here only when two roots share an actual resource abstraction; do not use remote-state coupling for values already present in `infrastructure/contract/home-lab.yml`.
