#!/bin/bash
# One attempt to create the free Oracle A1 server. Runs from GitHub Actions.
set -u
T="$OCI_TENANCY"
NAME=ssz-n8n-server

notify() {  # open a GitHub issue -> owner gets an email
  gh issue create --title "$1" --body "$2" >/dev/null 2>&1 || true
}

EXIST=$(oci compute instance list -c "$T" --display-name "$NAME" --all \
  --query 'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | [0].id' --raw-output 2>/dev/null)
if [ -n "$EXIST" ] && [ "$EXIST" != "None" ] && [ "$EXIST" != "null" ]; then
  echo "Server already exists: $EXIST"; echo "DONE=1" >> "$GITHUB_ENV"; exit 0
fi

AD=$(oci iam availability-domain list -c "$T" --query 'data[0].name' --raw-output)
VCN=$(oci network vcn list -c "$T" --display-name ssz-vcn --query 'data[0].id' --raw-output)
SUB=$(oci network subnet list -c "$T" --vcn-id "$VCN" --query 'data[0].id' --raw-output)
IMG=$(oci compute image list -c "$T" --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC \
  --query 'data[?!contains("display-name",`Minimal`)] | [0].id' --raw-output)
echo "AD=$AD SUB=${SUB:0:40}... IMG=${IMG:0:40}..."

for CFG in '{"ocpus":2,"memoryInGBs":12}' '{"ocpus":1,"memoryInGBs":6}'; do
  OUT=$(oci --no-retry compute instance launch -c "$T" --availability-domain "$AD" \
    --shape VM.Standard.A1.Flex --shape-config "$CFG" --image-id "$IMG" --subnet-id "$SUB" \
    --assign-public-ip true --display-name "$NAME" \
    --ssh-authorized-keys-file ssh_key.pub --user-data-file cloud-init.sh 2>&1)
  if echo "$OUT" | grep -q '"lifecycle-state"'; then
    ID=$(echo "$OUT" | grep -o '"id": "ocid1.instance[^"]*"' | head -1 | cut -d'"' -f4)
    echo "SUCCESS $CFG $ID"
    oci compute instance get --instance-id "$ID" --wait-for-state RUNNING --max-wait-seconds 600 >/dev/null 2>&1
    IP=$(oci compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
    notify "SERVER BAN GAYA - IP $IP" "Oracle free server ban gaya. Size: $CFG. Public IP: $IP. Ab GoDaddy me A record lagao: Host = n8n, Points to = $IP. Ye job ab khud ruk jayega."
    echo "DONE=1" >> "$GITHUB_ENV"
    exit 0
  fi
  echo "$(date -u +%H:%M) $CFG: $(echo "$OUT" | grep -o '"message": "[^"]*"' | head -1)"
  sleep 20
done
exit 0
