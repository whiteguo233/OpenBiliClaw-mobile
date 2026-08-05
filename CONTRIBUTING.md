# Contributing

感谢参与 OpenBiliClaw Mobile。

## 从独立仓库导入现有项目

如果代码目前位于一个与本仓库没有共同 Git 历史的独立仓库，请不要直接
把那个仓库的分支作为 PR 来源。请按下面的方式提交：

1. 在 GitHub 上 Fork `whiteguo233/OpenBiliClaw-mobile`。
2. Clone 你的 fork，并从 `main` 创建新分支：

   ```bash
   git clone https://github.com/<你的用户名>/OpenBiliClaw-mobile.git
   cd OpenBiliClaw-mobile
   git switch -c feat/import-flutter-client
   ```

3. 将独立 Flutter 项目的工作区内容复制进来，保留本仓库的 `.git/`。
   不要复制以下内容：

   - `.git/`
   - `.dart_tool/`、`build/`
   - Android/iOS 签名文件和证书
   - API Key、Cookie、密码、本地后端地址等私密配置

4. 提交并推送：

   ```bash
   git add .
   git commit -m "feat: import Flutter mobile client"
   git push -u origin feat/import-flutter-client
   ```

5. 在 GitHub 上向 `whiteguo233/OpenBiliClaw-mobile:main` 创建 Pull Request。

## PR 最低要求

- 说明支持的平台及已手动验证的系统版本。
- 说明如何配置 OpenBiliClaw 后端地址。
- 不提交任何密钥、签名材料或个人配置。
- 尽量运行 `flutter analyze` 和 `flutter test`，并在 PR 中写明结果。
- 涉及 API、鉴权或发布流程时，在 PR 描述中单独列出。

## Commit

建议使用 Conventional Commits，例如：

```text
feat: import Flutter mobile client
fix: handle backend authentication failure
docs: add Android setup instructions
```
