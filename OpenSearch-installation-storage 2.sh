#!/bin/bash

# Ensure you run this script with sudo or root privileges

# Variables - Update with your own values
OPENSEARCH_VERSION="2.17.1"
OPENSEARCH_DOWNLOAD_URL="https://artifacts.opensearch.org/releases/bundle/opensearch/${OPENSEARCH_VERSION}/opensearch-${OPENSEARCH_VERSION}-linux-x64.tar.gz"
OPENSEARCH_DIR="/home/nvisionx"
DATA_DIR="/opt/vol2/data/opensearch"
USER_NAME="nvisionx"  # Replace with actual username
NODE_NAME="172.25.140.237"  # Replace with actual node name or IP
DISCOVERY_HOSTS=("172.25.140.236" "172.25.140.237" "172.25.140.238")  # Replace with actual IPs of other nodes
ADMIN_PASSWORD="U9l2ypds^QMkBOu2"  # Replace with actual admin password

# Step 1: Configure Firewall
echo "Configuring firewall..."
sudo firewall-cmd --zone=public --permanent --add-port=9200-9600/tcp
sudo firewall-cmd --zone=public --permanent --add-port=9200-9600/udp
sudo firewall-cmd --zone=public --permanent --add-source=172.25.140.0  # Replace with actual CIDR
sudo firewall-cmd --reload

# Step 2: Download and Extract OpenSearch
echo "Downloading and extracting OpenSearch ${OPENSEARCH_VERSION}..."
wget -q ${OPENSEARCH_DOWNLOAD_URL} -O opensearch-${OPENSEARCH_VERSION}.tar.gz
tar -xvf opensearch-${OPENSEARCH_VERSION}.tar.gz

# Step 3: Disable Swap and Update Virtual Memory
echo "Disabling swap and updating virtual memory settings..."
sudo swapoff -a
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Check if vm.max_map_count is updated
cat /proc/sys/vm/max_map_count

# Step 4: Create Folder Structure for OpenSearch
echo "Creating folder structure..."
sudo mkdir -p ${DATA_DIR}
sudo chown ${USER_NAME}:${USER_NAME} -R /opt/vol2/data/opensearch
sudo chmod 777 -R /opt/vol2/data/opensearch

# Step 5: Configure OpenSearch (opensearch.yml)
echo "Configuring OpenSearch..."
OPENSEARCH_YML="${OPENSEARCH_DIR}/opensearch-${OPENSEARCH_VERSION}/config/opensearch.yml"
# Uncomment and modify lines in opensearch.yml
sudo sed -i "s|#cluster.name: my-application|cluster.name: os-cluster|" ${OPENSEARCH_YML}
sudo sed -i "s|#node.name: node-1|node.name: ${NODE_NAME}|" ${OPENSEARCH_YML}
sudo sed -i "s|#path.data: /path/to/data|path.data: ${DATA_DIR}|" ${OPENSEARCH_YML}
sudo sed -i "s|#network.host: 192.168.0.1|network.host: ${NODE_NAME}|" ${OPENSEARCH_YML}
sudo sed -i "s|#http.port: 9200|http.port: 9200-9600|" ${OPENSEARCH_YML}
# Uncomment and modify the 'bootstrap.memory_lock' line
sudo sed -i "s|#bootstrap.memory_lock:.*|bootstrap.memory_lock: true|" ${OPENSEARCH_YML}
# Uncomment and modify the 'discovery.seed_hosts' line
sudo sed -i "s|#discovery.seed_hosts:.*|discovery.seed_hosts: [\"${DISCOVERY_HOSTS[0]}\", \"${DISCOVERY_HOSTS[1]}\", \"${DISCOVERY_HOSTS[2]}\"]|" ${OPENSEARCH_YML}
# Uncomment and modify the 'cluster.initial_cluster_manager_nodes' line
sudo sed -i "s|#cluster.initial_cluster_manager_nodes:.*|cluster.initial_cluster_manager_nodes: [\"${DISCOVERY_HOSTS[0]}\", \"${DISCOVERY_HOSTS[1]}\", \"${DISCOVERY_HOSTS[2]}\"]|" ${OPENSEARCH_YML}

# Step 5.1: Append new settings to opensearch.yml
echo "Appending new settings for tcp keepalive..."
echo "http.tcp.keep_idle: 300 # Timeout to keep idle connections open (e.g., 5 minutes)" | sudo tee -a ${OPENSEARCH_YML}
echo "http.tcp.keep_interval: 60 # Interval between keepalive probes" | sudo tee -a ${OPENSEARCH_YML}

# Output completion message
echo "OpenSearch configuration updated successfully!"

# Step 6: Adjust JVM Settings (jvm.options)
echo "Adjusting JVM settings..."
JVM_OPTIONS="${OPENSEARCH_DIR}/opensearch-${OPENSEARCH_VERSION}/config/jvm.options"
sudo sed -i 's/-Xms1g/-Xms32g/' ${JVM_OPTIONS}  # Set heap size to 32GB for 64GB system
sudo sed -i 's/-Xmx1g/-Xmx32g/' ${JVM_OPTIONS}

# Step 7: Set File Descriptors
#echo "Setting file descriptors..."
#echo "${USER_NAME}  soft  memlock unlimited" | sudo tee -a /etc/security/limits.conf
#echo "${USER_NAME}  hard  memlock unlimited" | sudo tee -a /etc/security/limits.conf

# Step 8: Configure Admin Password
echo "Setting admin password..."
export OPENSEARCH_INITIAL_ADMIN_PASSWORD=${ADMIN_PASSWORD}

# Step 9: Create and Enable OpenSearch Service
echo "Creating systemd service file for OpenSearch..."

# Create the systemd service file
sudo tee /etc/systemd/system/opensearch.service > /dev/null <<EOF
[Unit]
Description=OpenSearch
Documentation=https://opensearch.org/docs/
After=network.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
Environment=OPENSEARCH_INITIAL_ADMIN_PASSWORD=${ADMIN_PASSWORD}
ExecStart=/bin/bash /home/ec2-user/opensearch-2.17.1/opensearch-tar-install.sh
LimitNOFILE=infinity
LimitMEMLOCK=infinity
WorkingDirectory=${OPENSEARCH_DIR}/opensearch-${OPENSEARCH_VERSION}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the OpenSearch service
echo "Enabling and starting OpenSearch service..."
sudo systemctl daemon-reload
sudo systemctl enable opensearch.service
sudo systemctl start opensearch.service

# Step 10: Test OpenSearch Setup
echo "Testing OpenSearch setup..."
sleep 30  # Wait for OpenSearch to start up
curl -X GET -u 'admin:${ADMIN_PASSWORD}' -k "https://${NODE_NAME}:9200/_cluster/health?pretty"
echo "OpenSearch setup complete!"

