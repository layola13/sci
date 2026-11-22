# net/tcp — RESERVED (Phase 1)

Reserved by the Phase 1 module plan. There is no standalone TCP file
today: TCP stream/listener APIs live in `net/socket/net.sa` and
`net/socket/net.sai`. Do not add files here until `net.sa` is split
in a later phase; that split must keep the `net/socket/` surface
working (shim or re-export) or record the break.
