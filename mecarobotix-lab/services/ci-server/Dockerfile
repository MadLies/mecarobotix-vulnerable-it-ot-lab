FROM jenkins/jenkins:lts-jdk17

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      curl git jq openssh-client ca-certificates zip unzip socat iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/mecarobotix-ci /ci-artifacts /var/log/mecarobotix-ci \
    && chown -R jenkins:jenkins /opt/mecarobotix-ci /ci-artifacts /var/log/mecarobotix-ci

COPY ci-scripts/ /opt/mecarobotix-ci/
COPY entrypoint.sh /usr/local/bin/mecarobotix-ci-entrypoint

RUN chmod -R 0777 /opt/mecarobotix-ci /ci-artifacts /var/log/mecarobotix-ci \
    && find /opt/mecarobotix-ci -type f -name "*.sh" -exec chmod +x {} \; \
    && chmod +x /usr/local/bin/mecarobotix-ci-entrypoint

USER jenkins

EXPOSE 8443

ENTRYPOINT ["/configure-network.sh", "/usr/local/bin/mecarobotix-ci-entrypoint"]
