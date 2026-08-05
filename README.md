# OpenBiliClaw Mobile

OpenBiliClaw 的官方移动客户端仓库。客户端连接用户自己运行的
[OpenBiliClaw](https://github.com/whiteguo233/OpenBiliClaw) 后端。

仓库现已开放社区贡献。首个 Flutter 客户端导入请通过 Pull Request
提交，方便维护者检查 API 兼容性、鉴权、构建配置和发布流程。

## 提交现有 Flutter 客户端

1. Fork 本仓库。
2. 从 fork 的 `main` 创建功能分支，例如 `feat/import-flutter-client`。
3. 将现有 Flutter 项目文件复制到该分支，但不要复制原项目的 `.git/`、
   `.dart_tool/`、`build/`、签名文件、密钥或本地配置。
4. 本地确认 `flutter analyze` 和 `flutter test` 可以运行。
5. 推送分支并向本仓库的 `main` 提交 Pull Request。

详细要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)
