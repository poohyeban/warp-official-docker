# Official WARP in Docker

Debian 12 slim + Cloudflare 官方 `cloudflare-warp` 软件包。没有修改客户端，
没有第三方 WARP 实现。支持 `docker exec` 管理与 shell 调试。

## 当前验证边界

这是交给 GitHub 构建的首版配置，不是已经验证通网的镜像。
本地检查了 shell/YAML；本地没有 Docker，未执行镜像构建、daemon 启动或 WARP 注册。
GitHub 工作流会构建 amd64 镜像并运行 `warp-cli --help`，通过后发布。
该检查不等于代理通网测试；仍需在 VPS 上按下文验收。
NET_ADMIN 和 TUN 是兼容性起点，尚未验证它们在纯代理模式下是否均可省去。
不提供 privileged、宿主网络或 Docker socket 挂载。

## 在 GitHub 构建

1. 新建仓库（本项目为 `poohyeban/warp-official-docker`），将本目录**内容**提交到 `main` 根目录，
   包括 `.github/workflows/build.yml`。不要只上传 ZIP，或再套一层目录。
2. Actions → Build and publish WARP。推送 main 自动运行，也可手动 Run workflow。
3. 使用自动提供的 GITHUB_TOKEN 发布，无需添加个人 token。
   如组织策略禁止 packages:write，需要管理员放行；不要把 token 写到仓库。
4. 成功后镜像是 `ghcr.io/<用户名或组织>/<仓库名>:latest`，名称自动转小写。
   另有 `:sha-<完整提交SHA>` 标签用于固定版本和回滚。
5. GHCR 包可能默认私有。若希望无需登录拉取，需自行将 Package visibility 设为 Public。
   仓库公开不应被当作包已公开的保证；私有包需在 VPS 登录 GHCR。

本项目镜像：`ghcr.io/poohyeban/warp-official-docker:latest`。
构建不会注册 WARP、不会连接用户 VPS，也不会自动改变包可见性。

## 快速部署（Docker Compose）

将 compose.yaml 放到 VPS 的项目目录。先阅读并接受 Cloudflare 的服务条款，
再在该目录的 `.env` 中配置：

```dotenv
WARP_IMAGE=ghcr.io/poohyeban/warp-official-docker:latest
WARP_ACCEPT_TOS=true
WARP_AUTO_INIT=true
```

```sh
docker compose pull
docker compose up -d
docker logs --tail 100 warp
docker exec warp warp-cli status
curl --max-time 30 --proxy socks5h://127.0.0.1:1080 https://www.cloudflare.com/cdn-cgi/trace
```

确认 `warp=on` 或 `warp=plus`。未确认前不要把生产流量切过去。
如果 /dev/net/tun 不存在，应先检查 VPS 的 TUN 支持，不要盲目加 privileged。
旧版 Docker 的 loopback 端口发布隔离存在历史问题，应使用受支持的新版本并检查防火墙。

## 手动管理

```sh
docker exec -it warp bash
docker exec warp warp-cli --help
docker exec warp warp-cli settings
docker exec warp warp-cli status
docker exec warp warp-cli disconnect
docker exec warp warp-cli connect
```

自动初始化仅在数据卷没有 `.container-initialized` 且显式启用时执行：
注册（已有注册则复用）、`mode proxy`、`proxy port 40000`、`connect`。
标记只代表配置命令成功，不代表隧道已连通。重启不会重设模式、端口或强制 connect；
连接恢复由 WARP 自己处理，需在 VPS 验收。失败时日志可查看，容器会按策略重启。

也可 `WARP_AUTO_INIT=false` 后自行执行（首次仍需接受服务条款）：

```sh
docker exec warp warp-cli --accept-tos registration new
docker exec warp warp-cli --accept-tos mode proxy
docker exec warp warp-cli --accept-tos proxy port 40000
docker exec warp warp-cli --accept-tos connect
```

这些命令取决于所安装官方版本；遇到参数变化先查看 `warp-cli --help`、
`warp-cli mode --help` 和 `warp-cli proxy --help`，不要套用社区客户端的 `warp run`。
如自行改 WARP 内部代理端口，同时调整 `.env` 中 WARP_PROXY_PORT 并重建容器。
若手动改成其他模式导致代理不再监听，宿主的 SOCKS 入口当然也不能继续使用。

## 网络和数据

宿主 127.0.0.1:1080 → 容器 socat:1080 → 容器 WARP 127.0.0.1:40000。
socat 只是 TCP 转发；不声称支持 SOCKS UDP ASSOCIATE，首版只验收 TCP。
WARP 配置与注册保存在命名卷 `/var/lib/cloudflare-warp`，其中包含敏感凭据，
不要提交或打包到 GitHub。不要执行 `docker compose down -v`，除非确实要清除身份。
正常更新使用 `docker compose pull && docker compose up -d`。
没有宿主网络模式，WARP 在容器中的路由变化不会直接修改宿主默认路由，
但 Docker 自身会正常创建 bridge/NAT 规则。
容器内部代理无认证；不要把 1080 发布到公网，也不要让不可信容器加入此网络。

宿主机 Xray 的 SOCKS 出站可使用：

```json
{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":1080}]}}
```

这只是 outbound 片段，需自行添加匹配的 routing 规则。
若 Xray 也在 Docker 中，它的 127.0.0.1 不是宿主；应使用受控共享网络与 `warp:1080`。

## 维护范围

- 固定官方包版本 2026.7.1377.0；更新 Dockerfile 的 WARP_VERSION 后重建。
- Debian 基础标签与 apt 系统依赖没有全部锁 digest/版本，不承诺位级可复现。
- 官方包带有桌面库依赖，镜像不会像纯静态代理程序一样小；不强行忽略依赖。
- 本项目仅封装安装与启动。官方软件及 WARP 服务受 Cloudflare 自身条款约束，
  未对其闭源二进制进行源码审计；发布镜像前需自行确认适用的使用与分发条款。
- 首版没有 SBOM、漏洞扫描或真实网络 CI，不能称为安全认证。
- 建议验收：首次连通、重启保留配置、手动断开/重连、代理无法从公网访问、
  宿主 SSH 和默认出口不受影响、镜像更新后身份保留。

参考：[官方 Linux 文档](https://developers.cloudflare.com/warp-client/get-started/linux/)、
[官方包仓库](https://pkg.cloudflareclient.com/)、
[GitHub 镜像发布](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)。
