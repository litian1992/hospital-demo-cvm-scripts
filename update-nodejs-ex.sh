#!/bin/bash

# Script for setting up nodejs-ex RHEL VM
# This runs on first boot to configure the VM to pull and run the container

function setup_nodejs_ex() {
packages=("podman" "podman-docker" "firewalld" "nginx" "trustee-guest-components")
for pkg in $packages; do
    dnf install -y $pkg
done

# Pull secret for OpenShift image registry
cat /root/.docker/config.json <<'EOF'
{
  "auths": {
    "image-registry.openshift-image-registry.svc:5000": {
      "auth": "REPLACE_WITH_BASE64_TOKEN"
    },
    "default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io": {
      "auth": "REPLACE_WITH_BASE64_TOKEN"
    }
  }
}
EOF
chmod 600 /root/.docker/config.json

# SSL of Trustee server
cat /etc/trusteeserver.crt <<'EOF'
REPLACE_WITH_TRUSTEE_SERVER_SSL
EOF

# Pull latest image and run
cat /usr/local/bin/update-nodejs-ex.sh <<'EOF'
#!/bin/bash
set -e
/usr/bin/podman rm -f nodejs-ex
  # Get decryption key of the container with an attestation
echo "=== Fetch container decryption key ==="
/usr/bin/trustee-attester --url https://trusteeserver:8080 --cert-file /etc/trusteeserver.crt \
  --path default/test/container_key | base64 -d > /root/container_key.pem

echo "=== Updating nodejs-ex container ==="
/usr/bin/podman pull --decryption-key /root/container_key.pem \
  default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io/janine-dev/nodejs-ex:latest
rm -f /root/container_key.pem

echo "✅ nodejs-ex updated successfully"
/usr/bin/podman run --rm \
  --name nodejs-ex \
  -p 8080:8080 \
  -e NODE_ENV=production \
  -e PORT=8080 \
  default-route-openshift-image-registry.apps.uhfgfgde.eastus.aroapp.io/janine-dev/nodejs-ex:latest
EOF
chmod 755 /usr/local/bin/nodejs-ex-update.sh

# Systemd service for nodjs-ex
cat /etc/systemd/system/nodejs-ex.service <<'EOF'
[Unit]
Description=Node.js Example Application (from OpenShift)
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
Restart=always
RestartSec=10
TimeoutStartSec=300
ExecStart=/usr/local/bin/nodejs-ex-update.sh
ExecStop=/usr/bin/podman stop -t 10 nodejs-ex
[Install]
WantedBy=multi-user.target
EOF
chmod 644 /etc/systemd/system/nodejs-ex.service

# Nginx reverse proxy configuration
cat /etc/nginx/conf.d/nodejs-ex.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://localhost:8080/health;
        access_log off;
    }
}
EOF
chmod 644 /etc/nginx/conf.d/nodejs-ex.conf

# Configure firewall
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Enable and start nodejs-ex service
systemctl daemon-reload
systemctl enable nodejs-ex.service
systemctl start nodejs-ex.service

# Wait for service to start
sleep 10

# Log status
systemctl status nodejs-ex.service --no-pager || true
podman ps -a
}
#end function setup_nodejs_ex

if ! { systemctl is-active nodejs-ex.service > /dev/null; }; then
    setup_nodejs_ex
else
    systemctl restart nodejs-ex.service
fi
