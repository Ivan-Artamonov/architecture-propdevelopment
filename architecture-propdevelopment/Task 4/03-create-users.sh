#!/usr/bin/env bash
# Использование: ./03-create-user.sh <имя> <группа> [<группа2> ...]
# Пример:   ./03-create-user.sh a.petrov devops
# По-умолчанию сам создаст 4 юзеров

set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-minikube}"
CLUSTER="${KUBE_CLUSTER:-minikube}"
OUT_DIR="${OUT_DIR:-$(dirname "$0")/users}"

if [ $# -eq 0 ]; then
  "$0" a.petrov  devops
  "$0" s.ivanova security
  "$0" d.smirnov team-sales
  "$0" m.orlova  observers
  echo
  echo "Создано пользователей: 4. Каталог: $OUT_DIR"
  exit 0
fi

if [ $# -lt 2 ]; then
  echo "использование: $0                      # завести всех" >&2
  echo "               $0 <имя> <группа> [...]  # завести одного" >&2
  exit 1
fi

USER_NAME="$1"; shift
GROUPS_SUBJ=""
for g in "$@"; do GROUPS_SUBJ="${GROUPS_SUBJ}/O=${g}"; done

mkdir -p "$OUT_DIR"
KEY="$OUT_DIR/$USER_NAME.key"
CSR="$OUT_DIR/$USER_NAME.csr"
CRT="$OUT_DIR/$USER_NAME.crt"
KUBECONFIG_FILE="$OUT_DIR/$USER_NAME.kubeconfig"

echo "==> [$USER_NAME] закрытый ключ"
openssl genrsa -out "$KEY" 2048 2>/dev/null
chmod 600 "$KEY"

echo "==> [$USER_NAME] запрос на сертификат: CN=$USER_NAME$GROUPS_SUBJ"
openssl req -new -key "$KEY" -out "$CSR" -subj "/CN=$USER_NAME$GROUPS_SUBJ"

# Старый CSR с тем же именем мешает создать новый
kubectl --context "$CONTEXT" delete csr "$USER_NAME" --ignore-not-found >/dev/null 2>&1

echo "==> [$USER_NAME] отправка запроса в кластер"
cat <<YAML | kubectl --context "$CONTEXT" apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USER_NAME
spec:
  request: $(base64 < "$CSR" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000
  usages:
    - client auth
YAML

echo "==> [$USER_NAME] подпись запроса"
kubectl --context "$CONTEXT" certificate approve "$USER_NAME" >/dev/null

# Кластер выдает сертификат не мгновенно
for i in $(seq 1 30); do
  CERT_B64=$(kubectl --context "$CONTEXT" get csr "$USER_NAME" -o jsonpath='{.status.certificate}' 2>/dev/null || true)
  [ -n "$CERT_B64" ] && break
  sleep 1
done
if [ -z "${CERT_B64:-}" ]; then
  echo "ОШИБКА: кластер не выдал сертификат для $USER_NAME" >&2
  exit 1
fi
echo "$CERT_B64" | base64 -d > "$CRT"

echo "==> [$USER_NAME] персональный kubeconfig"
CA_CRT=$(mktemp)
kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER\")].cluster.certificate-authority}" > /tmp/ca_path.$$ 2>/dev/null || true
CA_PATH=$(cat /tmp/ca_path.$$); rm -f /tmp/ca_path.$$
SERVER=$(kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER\")].cluster.server}")

kubectl --kubeconfig "$KUBECONFIG_FILE" config set-cluster "$CLUSTER" \
  --server="$SERVER" --certificate-authority="$CA_PATH" --embed-certs=true >/dev/null
kubectl --kubeconfig "$KUBECONFIG_FILE" config set-credentials "$USER_NAME" \
  --client-certificate="$CRT" --client-key="$KEY" --embed-certs=true >/dev/null
kubectl --kubeconfig "$KUBECONFIG_FILE" config set-context "$USER_NAME" \
  --cluster="$CLUSTER" --user="$USER_NAME" >/dev/null
kubectl --kubeconfig "$KUBECONFIG_FILE" config use-context "$USER_NAME" >/dev/null
rm -f "$CA_CRT"

echo "==> [$USER_NAME] готово: $KUBECONFIG_FILE"
echo "    проверить: kubectl --kubeconfig $KUBECONFIG_FILE get pods"
