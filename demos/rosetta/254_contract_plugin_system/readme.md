# 254 - Contract Plugin System

This tree keeps the plugin host contract separate from the implementation.

- `host/plugin_host.sa` describes the public dispatch entry point.
- `impl/plugin_impl.sa` exports the plugin implementation.
- `consumer/plugin_consumer.sa` imports both and validates the dispatch result.
