#!/usr/bin/env bash
set -euo pipefail

NS="vdiforge-netpol-test"
IMAGE="registry.k8s.io/e2e-test-images/agnhost:2.53"

cleanup() {
  kubectl delete namespace "${NS}" --ignore-not-found=true --wait=true --timeout=120s >/dev/null 2>&1 || true
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

curl_from_client() {
  kubectl exec -n "${NS}" netpol-client -- \
    curl -fsS --max-time 5 http://netpol-server:8080/hostname >/dev/null 2>&1
}

wait_for_client_access() {
  local description="$1"

  for _ in $(seq 1 24); do
    if curl_from_client; then
      return 0
    fi
    sleep 5
  done

  fail "${description}"
}

trap cleanup EXIT

cleanup
kubectl create namespace "${NS}" >/dev/null
kubectl label namespace "${NS}" app.kubernetes.io/part-of=vdiforge vdiforge.io/phase=3 >/dev/null

kubectl run netpol-server \
  -n "${NS}" \
  --image="${IMAGE}" \
  --restart=Never \
  --labels=app=netpol-server \
  --command -- /agnhost netexec --http-port=8080 --udp-port=-1 >/dev/null

kubectl expose pod netpol-server -n "${NS}" --port=8080 --target-port=8080 >/dev/null

kubectl run netpol-client \
  -n "${NS}" \
  --image="${IMAGE}" \
  --restart=Never \
  --labels=app=netpol-client \
  --command -- /agnhost pause >/dev/null

kubectl wait pod/netpol-server -n "${NS}" --for=condition=Ready --timeout=180s >/dev/null
kubectl wait pod/netpol-client -n "${NS}" --for=condition=Ready --timeout=180s >/dev/null

wait_for_client_access "initial client-to-server traffic did not pass before NetworkPolicy"

cat <<YAML | kubectl apply -n "${NS}" -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-netpol-server-ingress
spec:
  podSelector:
    matchLabels:
      app: netpol-server
  policyTypes:
    - Ingress
YAML

sleep 5

if curl_from_client >/dev/null 2>&1; then
  fail "traffic was still allowed after deny NetworkPolicy"
fi

cat <<YAML | kubectl apply -n "${NS}" -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-netpol-server
spec:
  podSelector:
    matchLabels:
      app: netpol-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: netpol-client
      ports:
        - protocol: TCP
          port: 8080
YAML

sleep 5

wait_for_client_access "explicit allow NetworkPolicy did not restore intended traffic"

echo "PASS: NetworkPolicy deny and allow behavior verified"
