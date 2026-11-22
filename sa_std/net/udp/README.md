# net/udp — RESERVED (Phase 1)

Reserved by the Phase 1 module plan. There is no standalone UDP file
today: UDP socket APIs live in `net/socket/net.sa` and
`net/socket/net.sai`. Do not add files here until `net.sa` is split
in a later phase.
