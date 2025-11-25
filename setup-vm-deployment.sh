#!/bin/bash
#
# Setup script for nodejs-ex VM deployment via ArgoCD
#
# This creates the necessary secrets for ArgoCD to deploy VMs
#

set -e

NAMESPACE="azure-infrastructure"

echo "=== Setting up VM Deployment Prerequisites ==="

# Create namespace
echo "Creating namespace: $NAMESPACE"
oc create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/nodejs-ex-vm-key ]; then
    echo "Generating SSH key for VM access..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/nodejs-ex-vm-key -N "" -C "nodejs-ex-vm-key"
fi

# Create SSH key secret
echo "Creating SSH key secret..."
oc create secret generic azure-ssh-key \
    --from-file=id_rsa=~/.ssh/nodejs-ex-vm-key \
    --from-file=id_rsa.pub=~/.ssh/nodejs-ex-vm-key.pub \
    -n $NAMESPACE \
    --dry-run=client -o yaml | oc apply -f -

# Create Azure credentials secret (already exists in the YAML, but can override)
echo "Azure credentials secret will be created from YAML manifest"

# Optional: Expose OpenShift image registry
echo ""
echo "=== Exposing OpenShift Image Registry ==="
oc patch configs.imageregistry.operator.openshift.io/cluster \
    --type merge \
    --patch '{"spec":{"defaultRoute":true}}' || echo "Route already exposed"

# Get registry route
REGISTRY_ROUTE=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not exposed yet")

echo ""
echo "============================================"
echo "✅ Setup Complete!"
echo ""
echo "OpenShift Registry: $REGISTRY_ROUTE"
echo ""
echo "Next steps:"
echo "1. Deploy the ArgoCD Application:"
echo "   oc apply -f applications/nodejs-ex-vm-deployment.yaml"
echo ""
echo "2. Watch the deployment:"
echo "   oc get job -n $NAMESPACE -w"
echo ""
echo "3. Check VM logs:"
echo "   oc logs -n $NAMESPACE job/deploy-nodejs-ex-vm"
echo ""
echo "4. Get VM IP:"
echo "   az vm show -d -g nodejs-ex-vm-rg -n nodejs-ex-rhel-vm --query publicIps -o tsv"
echo "============================================"
