# 256 - Contract Panic Handler Propagate

This tree splits the panic hook contract between the public declaration and the host handler.

- `iface/panic.sai` describes the panic hook signature.
- `host/panic_handler.sa` exports the hook implementation.
- `consumer/panic_consumer.sa` calls into the hook and checks the propagated value.
