# Sing-box Universal Survivor (全能生存版)
**Author:** [@rocky-yam-reburial](https://github.com/rocky-yam-reburial)

专为全平台环境（独立服务器 / 独立IP VPS / NAT KVM / NAT LXC / OpenWrt）打造的终极代理面板。向上完美发挥主流机型性能，向下兼容极其恶劣的极限环境（无 bash、无 curl、严苛 IO 与内存限制）。

## 🌟 核心突破
- **全平台自适应**：100% POSIX 纯 `sh` 标准，底层使用纯 `wget` 驱动，兼容极致精简系统（如 Alpine）。
- **抗母鸡 QoS 惩罚**：进程级零日志消除 Disk I/O 读写，深度压制 Go 内存 (`GOMEMLIMIT=30MiB`) 杜绝 OOM。
- **免域黑科技**：无需 80 端口与真实域名。内置自动生成高强度 ECC 自签证书，完美驱动 Hysteria2 与 TUIC。
- **双擎 Keeper 智能守护**：智能适配 Systemd 与 OpenRC，每分钟高频探活，每日凌晨 4 点清理僵尸句柄。

## 🚀 极速部署
为兼容极限环境，请直接使用 `sh` 运行本脚本：
```sh
wget -O install.sh [https://raw.githubusercontent.com/rocky-yam-reburial/Sing-box-Universal-Survivor/main/install.sh](https://raw.githubusercontent.com/rocky-yam-reburial/Sing-box-Universal-Survivor/main/install.sh) && sh install.sh

🛠️ 支持的协议组合 (无缝热切换)
免域全家桶 (推荐): VLESS-Reality / SS / AnyTLS / Hysteria2 / TUIC (全系免域名直接跑)

正规全量包: 需真实域名，增加 Naive 协议

独立协议包: 可单独部署 Hysteria2 或 TUIC (自带证书)
