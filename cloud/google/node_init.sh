#! /bin/bash
export DATA_DIR=/data
export DATA_DEV=/dev/disk/by-id/google-persistent-disk-1

sudo mkdir ${DATA_DIR}
sudo /usr/share/google/safe_format_and_mount \
  -m "mkfs.ext4 -F" ${DATA_DEV} ${DATA_DIR}

# Install the Stackdriver agent to pass metrics to Stackdriver Monitoring.
AGENT_INSTALL_SCRIPT="stack-install.sh"
EXPECTED_SHA256="3d298c1e8a06efa08bbf237cd663710ae124c631fc976f70098f0fde642bb29b  ./${AGENT_INSTALL_SCRIPT}"
curl -O https://repo.stackdriver.com/${AGENT_INSTALL_SCRIPT}
if ! echo "${EXPECTED_SHA256}" | sha256sum --quiet -c; then
  echo "Got ${AGENT_INSTALL_SCRIPT} with sha256sum "
  sha256sum ./${AGENT_INSTALL_SCRIPT}
  echo "But expected:"
  echo "${EXPECTED_SHA256}"
  echo "${AGENT_INSTALL_SCRIPT} may have been updated, verify the new sum at"
  echo "https://cloud.google.com/monitoring/agent/install-agent and update"
  echo "this script with the new sha256sum if necessary."
  exit 1
fi

sudo bash ./${AGENT_INSTALL_SCRIPT} --write-gcm

# Install google-fluentd which pushes application log files up into the Google
# Cloud Logs Monitor.
AGENT_INSTALL_SCRIPT="install-logging-agent.sh"
EXPECTED_SHA256="8db836510cf65f3fba44a3d49265ed7932e731e7747c6163da1c06bf2063c301  ./${AGENT_INSTALL_SCRIPT}"
curl -sSO https://dl.google.com/cloudagents/${AGENT_INSTALL_SCRIPT}
if ! echo "${EXPECTED_SHA256}" | sha256sum --quiet -c; then
  echo "Got ${AGENT_INSTALL_SCRIPT} with sha256sum "
  sha256sum ./${AGENT_INSTALL_SCRIPT}
  echo "But expected:"
  echo "${EXPECTED_SHA256}"
  echo "${AGENT_INSTALL_SCRIPT} may have been updated, verify the new sum at"
  echo "https://cloud.google.com/logging/docs/agent/installation and update"
  echo "this script with the new sha256sum if necessary."
  exit 1
fi

sudo bash ./${AGENT_INSTALL_SCRIPT}

# Examine what kind of Docker image is on this machine to determine what to log.
DOCKER_REPOS_FILE=$(mktemp)
docker images --format '{{ .Repository }}' > "${DOCKER_REPOS_FILE}"

if grep '/ct-server$' "${DOCKER_REPOS_FILE}"; then
  CT_LOGS_PREFIX="${DATA_DIR}/ctlog/logs/ct-server"
elif grep '/ct-mirror$' "${DOCKER_REPOS_FILE}"; then
  CT_LOGS_PREFIX="${DATA_DIR}/ctmirror/logs/ct-mirror"
fi

rm "${DOCKER_REPOS_FILE}"

if [[ -n "${CT_LOGS_PREFIX}" ]]; then
  sudo cat > /etc/google-fluentd/config.d/ct-info.conf <<EOF
<source>
  type tail
  format none
  path ${CT_LOGS_PREFIX}.*.INFO.*
  pos_file ${CT_LOGS_PREFIX}.INFO.pos
  read_from_head true
  tag ct-info
</source>
<source>
  type tail
  format none
  path ${CT_LOGS_PREFIX}.*.ERROR.*
  pos_file ${CT_LOGS_PREFIX}.ERROR.pos
  read_from_head true
  tag ct-warn
</source>
<source>
  type tail
  format none
  path ${CT_LOGS_PREFIX}.*.WARNING.*
  pos_file ${CT_LOGS_PREFIX}.WARNING.pos
  read_from_head true
  tag ct-warn
</source>
<source>
  type tail
  format none
  path ${CT_LOGS_PREFIX}.*.FATAL.*
  pos_file ${CT_LOGS_PREFIX}.FATAL.pos
  read_from_head true
  tag ct-error
</source>
EOF
  sudo service google-fluentd restart
fi
# End google-fluentd stuff

cat > /etc/logrotate.d/docker <<EOF
/var/log/docker.log {
  rotate 7
  daily
  compress
  size=1M
  missingok
  delaycompress
  copytruncate
}
EOF
