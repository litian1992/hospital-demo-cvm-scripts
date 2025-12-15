#!/bin/bash

# Script for setting up nodejs-ex RHEL VM
# This runs on first boot to configure the VM to pull and run the container

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--quay-auth)
            quay_auth="$2"
            shift 2
            ;;
        -i|--image)
            image_name="$2"
            shift 2
            ;;
        -t|--trustee-url)
            trustee_url="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

function setup_nodejs_ex() {
packages="podman podman-docker firewalld nginx trustee-guest-components"
dnf install -y $packages

# Quay.io login
[ -d /root/.config/containers ] || mkdir -p /root/.config/containers
cat << EOF > /root/.config/containers/auth.json
{
  "auths": {
    "quay.io": {
      "auth": "$quay_auth"
    }
  }
}
EOF
chmod 600 /root/.config/containers/auth.json

# Pull latest image and run
cat << EOF > /usr/local/bin/nodejs-ex-update.sh
#!/bin/bash
set -e
/usr/bin/podman rm -f nodejs-ex
  # Get decryption key of the container with an attestation
echo "=== Fetch secret from Trustee server ==="
/usr/bin/trustee-attester --url $trustee_url \
  get-resource --path default/secret/example-secret 2> /dev/null | base64 -d

echo "=== Updating nodejs-ex container ==="
/usr/bin/podman pull \
  quay.io/$image_name
rm -f /root/container_key.pem

echo "✅ nodejs-ex updated successfully"
/usr/bin/podman run --rm \
  --name nodejs-ex \
  -p 8080:8080 \
  -e NODE_ENV=production \
  -e PORT=8080 \
  quay.io/$image_name
EOF
chmod 755 /usr/local/bin/nodejs-ex-update.sh

# Systemd service for nodjs-ex
cat << EOF > /etc/systemd/system/nodejs-ex.service
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
cat << EOF > /etc/nginx/conf.d/nodejs-ex.conf
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        proxy_pass http://localhost:8080/health;
        access_log off;
    }
}
EOF
chmod 644 /etc/nginx/conf.d/nodejs-ex.conf

# Configure firewall
#systemctl enable firewalld
#systemctl start firewalld
#firewall-cmd --permanent --add-service=http
#firewall-cmd --permanent --add-service=https
#firewall-cmd --permanent --add-port=8080/tcp
#firewall-cmd --reload

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
