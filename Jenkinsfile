pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds(abortPrevious: true)
    }

    environment {
        REGISTRY      = 'ghcr.io'
        NAMESPACE     = 'cicd-demo'                    // ← 换成你的 GitHub 用户名（GHCR 命名空间）
        APP_TAG       = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
        IMAGE_BACKEND = "${REGISTRY}/${NAMESPACE}/cicd-demo-backend:${APP_TAG}"
        IMAGE_FRONTEND= "${REGISTRY}/${NAMESPACE}/cicd-demo-frontend:${APP_TAG}"
        DEPLOY_HOST   = 'ubuntu@49.234.202.181'
        DEPLOY_SCRIPT = '/opt/apps/cicd-demo/scripts/deploy.sh'
    }

    stages {
        stage('① 检出') {
            steps { sh 'git log -1 --oneline' }
        }

        stage('② 后端测试') {
            agent {
                docker {
                    image 'python:3.11-slim'
                    args '-v jenkins-pip-cache:/tmp/pip-cache -e PIP_CACHE_DIR=/tmp/pip-cache'
                    reuseNode true
                }
            }
            steps {
                dir('demos/backend') {
                    // 用工作区 venv 而不是 pip --user：容器内 HOME 不可写时会报 /.local 权限错误
                    // 用 python -m pytest 而不是直接调 pytest：后者不会把当前目录加进 sys.path，会报 No module named 'app'
                    sh '''
                        python -m venv .venv
                        .venv/bin/pip install -r requirements.txt
                        .venv/bin/python -m pytest
                    '''
                }
            }
        }

        stage('③ 构建镜像') {
            steps {
                sh "docker build -f deploy/Dockerfile.backend  -t ${IMAGE_BACKEND}  demos/backend"
                sh "docker build -f deploy/Dockerfile.frontend -t ${IMAGE_FRONTEND} demos/frontend"
            }
        }

        stage('④ 冒烟测试') {
            steps {
                sh '''
                    docker rm -f smoke-api 2>/dev/null || true
                    docker run -d --name smoke-api -p 18000:8000 "$IMAGE_BACKEND"
                    for i in $(seq 1 20); do
                        if curl -fsS http://127.0.0.1:18000/healthz >/dev/null; then
                            echo "冒烟测试通过（第 ${i} 次）"; exit 0
                        fi
                        sleep 2
                    done
                    echo "冒烟测试失败，容器日志："; docker logs smoke-api; exit 1
                '''
            }
            post {
                always { sh 'docker rm -f smoke-api 2>/dev/null || true' }
            }
        }

        // ⑤⑥ 只在 main 跑：feature 分支只做"测试+构建+冒烟"，绝不碰生产
        stage('⑤ 推送镜像') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr-registry',
                                                  usernameVariable: 'REG_USER',
                                                  passwordVariable: 'REG_PASS')]) {
                    sh 'echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin ghcr.io'
                    sh "docker push ${IMAGE_BACKEND}"
                    sh "docker push ${IMAGE_FRONTEND}"
                }
            }
        }

        stage('⑥ 部署生产') {
            when { branch 'main' }
            steps {
                // 想加人工确认就把下面 input 的注释打开
                // input message: '确认部署生产？', ok: '部署', submitter: 'admin'
                withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh-key',
                                                   keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new ${DEPLOY_HOST} \
                          'sudo REGISTRY=${REGISTRY} REGISTRY_NAMESPACE=${NAMESPACE} \
                             bash ${DEPLOY_SCRIPT} ${APP_TAG}'
                    """
                }
            }
        }
    }

    post {
        failure { echo "构建失败：${env.BUILD_URL}console" }
        success { echo "本次构建完成，TAG=${APP_TAG}" }
        cleanup { cleanWs() }
    }
}