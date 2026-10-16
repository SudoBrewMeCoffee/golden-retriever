#!/bin/bash
# Enrol a ch-mirror guest in KRONOS Wazuh (CT130). Usage: sudo bash chm-wazuh-agent.sh <agent-name>
set -euo pipefail
NAME="$1"
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
cat > /etc/yum.repos.d/wazuh.repo <<'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
WAZUH_MANAGER=10.69.1.131 WAZUH_AGENT_NAME="$NAME" dnf -y -q install wazuh-agent-4.14.8
# Agent must not auto-upgrade past the manager
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/wazuh.repo
systemctl daemon-reload
systemctl enable --now wazuh-agent
sleep 5
systemctl is-active wazuh-agent
grep -iE "Connected to the server|Valid key|ERROR" /var/ossec/logs/ossec.log | tail -3
