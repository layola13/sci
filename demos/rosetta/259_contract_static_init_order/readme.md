# 259 - Contract Static Init Order

This tree keeps the init-order layout separate from the exported entry points.

- `layout/init_order.sal` records the slots used by the consumer.
- `bridge/init_bridge.sa` provides the two init stages.
- `consumer/init_consumer.sa` stores both stages in order and checks the sum.
