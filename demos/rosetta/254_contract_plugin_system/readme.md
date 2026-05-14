# 254 - Contract Plugin System

This tree keeps the plugin host contract separate from the implementation.

- `host/plugin_host.saasm` describes the public dispatch entry point.
- `impl/plugin_impl.saasm` exports the plugin implementation.
- `consumer/plugin_consumer.saasm` imports both and validates the dispatch result.
