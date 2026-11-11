# Jenkins 共享库（Shared Library）

把重复的流水线逻辑（构建镜像、部署、通知）抽成函数，多个项目复用。

## 目录约定

```
shared-library/
├── vars/          全局函数：文件名即函数名，内部必须实现 def call(...)
│   ├── buildImage.groovy
│   └── deployToServer.groovy
├── src/           普通 Groovy 类，按包名 import 使用
└── resources/     静态资源，用 libraryResource('xxx.sh') 读取
```

## 在 Jenkins 中注册

Manage Jenkins → System → **Global Pipeline Libraries**：

| 字段 | 值 |
| --- | --- |
| Name | `cicd-lib` |
| Default version | `main` |
| Retrieval method | Modern SCM → Git |
| Project Repository | 本仓库地址 |
| Library Path | `pipelines/jenkins/shared-library` |
| Allow default version to be overridden | 勾选（可按 tag 锁定版本） |

## 在 Jenkinsfile 中使用

```groovy
@Library('cicd-lib@main') _

pipeline {
    agent any
    stages {
        stage('构建并部署') {
            steps {
                script {
                    def image = buildImage(
                        name: 'cicd-demo-backend',
                        tag: env.BUILD_NUMBER,
                        dockerfile: 'deploy/Dockerfile.backend',
                        context: 'demos/backend'
                    )
                    echo "镜像已推送：${image}"
                    deployToServer(host: '49.234.202.181', tag: env.BUILD_NUMBER)
                }
            }
        }
    }
}
```

## 三条硬规矩

1. `@Library` 必须是文件第一行（下面紧跟的 `_` 是占位符，不能省）。
2. `vars/` 里的文件名 = 调用时的函数名，内部必须是 `def call(...)`。
3. 共享库里的 `sh` 双引号字符串中，shell 变量要写 `\$VAR` 转义，否则被 Groovy 先插值成空。

## 版本管理建议

- 团队协作用 `@main`，跟着仓库走。
- 生产流水线建议 `@v1.2.0` 锁定版本，避免共享库改动把线上流水线改崩。
- 共享库改动同样要走 PR + 测试，它比业务代码影响面更大。
