# 189 - Protobuf Varint Decode

## 目标特性 (Target Feature)
展示带 continuation bit 的 varint 解码循环。

## 当前示例 (Current Demo Shape)
1. SA 版本显式维护 `idx`、`shift`、`acc` 三个槽位，每轮读取一个 byte、提取低 7 位并决定是否继续。
2. 当前输入固定为 `[6, 0, 0]`，因此成功路径解码结果就是 `6`。
3. 这个 demo 关注 while/loop 形态的位移累加与退出条件，而不是 protobuf 全协议。

