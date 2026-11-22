# net/socket — socket API

Socket, TCP, UDP and Unix-socket API: the `net.*` companion set
(`net.sa` macros, `net.sai` externs, `net.sal` layout, `net.sla`
address-family constants for SLA).

TCP and UDP have no separate files yet: both live in this monolith.
`net/tcp/` and `net/udp/` are reserved for a future split of `net.sa`
(Phase 2+ work, not Phase 1). Do not add files there until that split.
