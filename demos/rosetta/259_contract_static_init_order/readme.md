# 259 - Contract Static Init Order

This tree keeps the init-order layout separate from the exported entry points.

- `layout/init_order.saasm-layout` records the slots used by the consumer.
- `bridge/init_bridge.saasm` provides the two init stages.
- `consumer/init_consumer.saasm` stores both stages in order and checks the sum.
