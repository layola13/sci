# 256 - Contract Panic Handler Propagate

This tree splits the panic hook contract between the public declaration and the host handler.

- `iface/panic.saasm-iface` describes the panic hook signature.
- `host/panic_handler.saasm` exports the hook implementation.
- `consumer/panic_consumer.saasm` calls into the hook and checks the propagated value.
