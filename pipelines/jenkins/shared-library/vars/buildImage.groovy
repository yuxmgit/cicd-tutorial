/**
 * 构建并推送镜像。
 *
 * 用法：
 *   buildImage(name: 'cicd-demo-backend', tag: env.BUILD_NUMBER,
 *              dockerfile: 'deploy/Dockerfile.backend', context: 'demos/backend')
 *
 * 返回：完整镜像地址
 */
def call(Map cfg = [:]) {
    def registry   = cfg.registry   ?: 'ccr.ccs.tencentyun.com'
    def namespace  = cfg.namespace  ?: 'default'
    def name       = cfg.name       ?: error('buildImage: 缺少 name 参数')
    def tag        = cfg.tag        ?: "${env.BUILD_NUMBER}"
    def dockerfile = cfg.dockerfile ?: 'Dockerfile'
    def context    = cfg.context    ?: '.'
    def credId     = cfg.registryCredentialId ?: 'tcr-registry'

    def image = "${registry}/${namespace}/${name}:${tag}"
    echo "准备构建镜像：${image}"

    retry(2) {
        sh "docker build -t ${image} -f ${dockerfile} ${context}"
    }

    withCredentials([usernamePassword(
        credentialsId: credId,
        usernameVariable: 'REG_USER',
        passwordVariable: 'REG_PASS'
    )]) {
        sh "echo \"\$REG_PASS\" | docker login -u \"\$REG_USER\" --password-stdin ${registry}"
        sh "docker push ${image}"
    }

    return image
}
