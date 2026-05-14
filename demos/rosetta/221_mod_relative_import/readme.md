# 221 - Mod Relative Import

## 目标特性 (Target Feature)
展示同一目录下经过多级相对路径解析的模块链。

## 文件结构
- `main.saasm` 作为入口。
- `helper.saasm` 转发到 `chain/step.saasm`。
- `chain/step.saasm` 再转到 `chain/deeper/seed.saasm`。

## 结果
- 编译通过，输出 `221`.
