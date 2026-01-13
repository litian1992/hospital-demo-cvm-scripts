#!/bin/bash

# Script for setting up nodejs-ex RHEL VM
# This runs on first boot to configure the VM to pull and run the container

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--quay-auth)
            export quay_auth="$2"
            shift 2
            ;;
        -i|--deid-image)
            export deid_image="$2"
            shift 2
            ;;
        -t|--trustee-url)
            export trustee_url="$2"
            shift 2
            ;;
        -s|--sidecar-image)
            export sidecar_image="$2"
            shift 2
            ;;
        -c|--connection-string)
            export connection_string="$2"
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
curl https://raw.githubusercontent.com/litian1992/hospital-demo-cvm-scripts/refs/heads/main/nodejs-ex-update.sh \
    -o /usr/local/bin/nodejs-ex-update.sh 2> /dev/null
chmod 755 /usr/local/bin/nodejs-ex-update.sh
bash /usr/local/bin/nodejs-ex-update.sh

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
# serves sidecar CDH resource
server {
    listen 127.0.0.1:8006;
        server_name localhost;

        location /cdh/resource/ {
        alias /srv/http/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        default_type application/octet-stream;
        add_header Cache-Control "no-store";
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
semanage port -a -t http_port_t -p tcp 8006
mkdir -p /srv/http; chcon -R -t httpd_sys_content_t /srv/http
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
