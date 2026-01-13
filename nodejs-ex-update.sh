#!/bin/bash
set -e

echo "=== Fetch secrets from Trustee server ==="
secrets=("server-cert" "server-key" "client-ca")
for secret in "${secrets[@]}"; do
    rm -f /srv/http/$secret
    /usr/bin/trustee-attester --url $trustee_url \
        get-resource --path default/$secret 2> /dev/null | base64 -d > /srv/http/$secret
done

# Create a pod to run de-id and sidecar
podman rm -f deid-roberta coco-secure-access
podman pod rm -f deid-pod

podman pod create --name deid-pod

echo "=== Start the sidecar ==="
podman run -d --network host \
  --name coco-secure-access \
  --pod deid-pod \
  -e TLS_KEY_URI=kbs:///server-key \
  -e TLS_CERT_URI=kbs:///server-cert \
  -e CLIENT_CA_URI=kbs:///client-ca \
  -e HTTPS_PORT="8443" \
  -e FORWARD_PORT="8080" \
  -e POD_NAME="deid-pod" \
  -e POD_NAMESPACE="default" \
  quay.io/$sidecar_image

echo "=== Start the de-id ==="
podman run -d \
  --name deid-roberta --network host \
  --pod deid-pod \
  -e UVICORN_DISABLE_IPV6=true \
  -e AZURE_STORAGE_CONNECTION_STRING="$connection_string" \
  quay.io/$deid_image
