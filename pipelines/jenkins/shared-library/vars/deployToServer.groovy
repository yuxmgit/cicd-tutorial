/**
 * 通过 SSH 触发生产服务器上的部署脚本。
 *
 * 用法：
 *   deployToServer(host: '49.234.202.181', user: 'ubuntu',
 *                  dir: '/opt/apps/cicd-demo', tag: env.BUILD_NUMBER)
 */
def call(Map cfg = [:]) {
    def host   = cfg.host   ?: error('deployToServer: 缺少 host 参数')
    def user   = cfg.user   ?: 'ubuntu'
    def dir    = cfg.dir    ?: '/opt/apps/cicd-demo'
    def tag    = cfg.tag    ?: error('deployToServer: 缺少 tag 参数')
    def credId = cfg.credentialsId ?: 'deploy-ssh-key'

    withCredentials([sshUserPrivateKey(credentialsId: credId, keyFileVariable: 'SSH_KEY')]) {
        // 注意：\$SSH_KEY 转义，保留给 shell 展开，避免被 Groovy 提前吃掉
        sh """
            ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new ${user}@${host} \\
              'cd ${dir} && sudo ./scripts/deploy.sh ${tag}'
        """
    }
}
