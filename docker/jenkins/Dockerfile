FROM jenkins/jenkins:lts-jdk17
USER root
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update -qq && apt-get install -y -qq docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*
USER jenkins
