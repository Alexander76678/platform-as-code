#!/bin/bash
set -e

TF_DIR="terraform"
INV_FILE="inventory/hosts.yml"

cd "$TF_DIR"
terraform output -json instance_ips > /tmp/ips.json

cd - > /dev/null

# Use jq to build the inventory
cat > "$INV_FILE" <<EOF
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/lbkey.pem
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    ghcr_user: "alexander76678"
    ghcr_token: "{{ vault_ghcr_token }}"
    #app name is on vars.yml

  children:
    appservers:
      vars:
        mongo_uri: "mongodb://$(jq -r '.lb.private_ip' /tmp/ips.json):27017"
      hosts:
        app1:
          ansible_host: $(jq -r '.app1.public_ip' /tmp/ips.json)
          private_ip: $(jq -r '.app1.private_ip' /tmp/ips.json)
        app2:
          ansible_host: $(jq -r '.app2.public_ip' /tmp/ips.json)
          private_ip: $(jq -r '.app2.private_ip' /tmp/ips.json)

    loadbalancers:
      hosts:
        lb:
          ansible_host: $(jq -r '.lb.public_ip' /tmp/ips.json)
          private_ip: $(jq -r '.lb.private_ip' /tmp/ips.json)

    databases:
      hosts:
        lb:
          ansible_host: $(jq -r '.lb.public_ip' /tmp/ips.json)
          private_ip: $(jq -r '.lb.private_ip' /tmp/ips.json)
EOF

echo "Inventory written to $INV_FILE"

