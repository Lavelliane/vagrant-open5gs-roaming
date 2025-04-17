#!/bin/bash
# Get service IPs from Kubernetes
SERVICES=$(microk8s kubectl get svc -n open5gs -o jsonpath='{range .items[*]}{.metadata.name}{","}{.spec.clusterIP}{"\n"}{end}')

# Start the ConfigMap
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  3gppnetwork.org.server: |
    3gppnetwork.org {
      hosts {
$(echo "$SERVICES" | while IFS="," read -r svc_name svc_ip; do
  # Home services have h- prefix, visiting have v- prefix
  if [[ "$svc_name" == h-* ]]; then
    base_name=${svc_name#h-}
    echo "        $svc_ip $base_name.5gc.mnc001.mcc001.3gppnetwork.org"
  elif [[ "$svc_name" == v-* ]]; then
    base_name=${svc_name#v-}
    echo "        $svc_ip $base_name.5gc.mnc070.mcc999.3gppnetwork.org"
  fi
done)
      }
    }
EOF