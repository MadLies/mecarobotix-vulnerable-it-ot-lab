#!/bin/sh
set -e

GITEA_URL="https://devops-server:3000"
GITEA_WORK_PATH="/data/gitea"
GITEA_CONFIG="$GITEA_WORK_PATH/conf/app.ini"
JENKINS_URL="https://ci-server:8443"
JENKINS_USER="jenkins_admin"
JENKINS_PASS="Admin123!"
JENKINS_JOB="sync-gitea-release-to-artifact-registry"

echo "[+] Waiting for Gitea to be ready..."

until curl -fsS "$GITEA_URL/api/healthz" >/dev/null 2>&1; do
  echo "    Gitea not ready yet..."
  sleep 5
done

echo "[+] Gitea is reachable."

echo "[+] Waiting for Jenkins CI job to be ready..."
until curl -fsS -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/job/$JENKINS_JOB/api/json" >/dev/null 2>&1; do
  echo "    Jenkins job not ready yet..."
  sleep 5
done

echo "[+] Jenkins CI job is ready."

echo "[+] Waiting for installed Gitea config..."
while ! grep -Eq '^[[:space:]]*INSTALL_LOCK[[:space:]]*=[[:space:]]*true' "$GITEA_CONFIG" 2>/dev/null; do
  echo "    Waiting for $GITEA_CONFIG with INSTALL_LOCK=true..."
  sleep 5
done

gitea_cli() {
  su git -c "gitea --config '$GITEA_CONFIG' --work-path '$GITEA_WORK_PATH' $*"
}

create_user() {
  USERNAME="$1"
  PASSWORD="$2"
  EMAIL="$3"
  ADMIN_FLAG="$4"

  if gitea_cli "admin user list" | grep -Eq "(^|[[:space:]])$USERNAME([[:space:]]|$)"; then
    echo "[+] Gitea user already exists: $USERNAME"
    return
  fi

  echo "[+] Creating Gitea user: $USERNAME"

  if [ "$ADMIN_FLAG" = "admin" ]; then
    gitea_cli "admin user create \
      --username '$USERNAME' \
      --password '$PASSWORD' \
      --email '$EMAIL' \
      --admin"
  else
    gitea_cli "admin user create \
      --username '$USERNAME' \
      --password '$PASSWORD' \
      --email '$EMAIL'"
  fi
}

create_user "gitea_admin" "Admin123!" "gitea_admin@mecarobotix.local" "admin"
create_user "dev01" "Dev123!" "dev01@mecarobotix.local" "user"
create_user "dev02" "Dev123!" "dev02@mecarobotix.local" "user"
create_user "tech01" "Tech123!" "tech01@mecarobotix.local" "user"
create_user "sec01" "Sec123!" "sec01@mecarobotix.local" "user"
create_user "svc_ci_robot_deploy" "SvcDeploy123!" "svc_ci_robot_deploy@mecarobotix.local" "admin"

echo "[+] Gitea users initialization completed."


echo "[+] Creating Gitea organization and repositories..."

GITEA_ADMIN="gitea_admin"
GITEA_PASS="Admin123!"
GITEA_OWNER="mecarobotix"
FIRMWARE_REPO="firmware-robot-a"
FIRMWARE_RELEASE_TAG="${FIRMWARE_RELEASE_TAG:-v1.0.0}"
FIRMWARE_RELEASE_NAME="${FIRMWARE_RELEASE_NAME:-Robot A firmware v1.0.0}"

if curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" "$GITEA_URL/api/v1/orgs/$GITEA_OWNER" >/dev/null 2>&1; then
  echo "[+] Gitea organization already exists: $GITEA_OWNER"
else
  echo "[+] Creating Gitea organization: $GITEA_OWNER"
  curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
    -X POST "$GITEA_URL/api/v1/orgs" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$GITEA_OWNER\",\"full_name\":\"MecaRobotix\"}" >/dev/null
fi

create_repo() {
  REPO="$1"

  if curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$REPO" >/dev/null 2>&1; then
    echo "[+] Repository already exists: $REPO"
    return
  fi

  echo "[+] Creating repository: $REPO"

  curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
    -X POST "$GITEA_URL/api/v1/orgs/$GITEA_OWNER/repos" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$REPO\", \"private\": false}" >/dev/null
}

create_repo "firmware-robot-a"
create_repo "firmware-robot-b"
create_repo "robot-maintenance-scripts"
create_repo "deployment-tools"
create_repo "infrastructure-docs"

add_repo_admin() {
  REPO="$1"
  USERNAME="$2"

  echo "[+] Granting admin access on $REPO to $USERNAME"
  curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
    -X PUT "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$REPO/collaborators/$USERNAME" \
    -H "Content-Type: application/json" \
    -d '{"permission":"admin"}' >/dev/null || true
}

for REPO in firmware-robot-a firmware-robot-b robot-maintenance-scripts deployment-tools infrastructure-docs; do
  add_repo_admin "$REPO" "svc_ci_robot_deploy"
done

create_release_webhook() {
  REPO="$1"
  ROBOT_TYPE="$2"
  ROBOT_HOST="$3"
  JENKINS_AUTH_HEADER="Basic $(printf '%s' "$JENKINS_USER:$JENKINS_PASS" | base64 | tr -d '\n')"
  WEBHOOK_URL="https://ci-server:8443/job/$JENKINS_JOB/buildWithParameters?ROBOT_TYPE=$ROBOT_TYPE&ROBOT_HOST=$ROBOT_HOST&FIRMWARE_REPO=$REPO&RELEASE_TAG=latest"
  CREATE_HOOK_PAYLOAD="{\"type\":\"gitea\",\"config\":{\"url\":\"$WEBHOOK_URL\",\"content_type\":\"json\",\"authorization_header\":\"$JENKINS_AUTH_HEADER\"},\"events\":[\"release\"],\"active\":true}"
  UPDATE_HOOK_PAYLOAD="{\"config\":{\"url\":\"$WEBHOOK_URL\",\"content_type\":\"json\",\"authorization_header\":\"$JENKINS_AUTH_HEADER\"},\"events\":[\"release\"],\"active\":true}"
  HOOKS_JSON="$(curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$REPO/hooks")"
  EXISTING_HOOK_ID="$(printf '%s' "$HOOKS_JSON" \
    | tr '{' '\n' \
    | grep "$JENKINS_JOB" \
    | sed -n 's/.*"id":[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    | head -n 1)"

  if [ -n "$EXISTING_HOOK_ID" ]; then
    echo "[+] Updating Jenkins release webhook for $REPO"
    curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
      -X PATCH "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$REPO/hooks/$EXISTING_HOOK_ID" \
      -H "Content-Type: application/json" \
      -d "$UPDATE_HOOK_PAYLOAD" >/dev/null || true
    return
  fi

  echo "[+] Creating Jenkins release webhook for $REPO"
  curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
    -X POST "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$REPO/hooks" \
    -H "Content-Type: application/json" \
    -d "$CREATE_HOOK_PAYLOAD" >/dev/null || true
}

trigger_jenkins_release_sync() {
  REPO="$1"
  ROBOT_TYPE="$2"
  ROBOT_HOST="$3"
  RELEASE_TAG_VALUE="$4"
  BUILD_URL="$JENKINS_URL/job/$JENKINS_JOB/buildWithParameters?ROBOT_TYPE=$ROBOT_TYPE&ROBOT_HOST=$ROBOT_HOST&FIRMWARE_REPO=$REPO&RELEASE_TAG=$RELEASE_TAG_VALUE"
  HEADER_FILE="/tmp/jenkins-trigger-headers"
  BODY_FILE="/tmp/jenkins-trigger-body"

  echo "[+] Triggering Jenkins release sync for $REPO:$RELEASE_TAG_VALUE"
  HTTP_STATUS="$(curl -sS -u "$JENKINS_USER:$JENKINS_PASS" \
    -D "$HEADER_FILE" \
    -o "$BODY_FILE" \
    -w '%{http_code}' \
    -X POST "$BUILD_URL")" || {
    echo "[!] Jenkins release sync trigger failed for $REPO:$RELEASE_TAG_VALUE"
    echo "[!] Webhook URL without credentials would be: https://ci-server:8443/job/$JENKINS_JOB/buildWithParameters?ROBOT_TYPE=$ROBOT_TYPE&ROBOT_HOST=$ROBOT_HOST&FIRMWARE_REPO=$REPO&RELEASE_TAG=$RELEASE_TAG_VALUE"
    return
  }

  case "$HTTP_STATUS" in
    2*|3*)
      ;;
    *)
      echo "[!] Jenkins release sync trigger returned HTTP $HTTP_STATUS"
      cat "$BODY_FILE" || true
      return
      ;;
  esac

  QUEUE_URL="$(awk 'tolower($1) == "location:" {print $2}' "$HEADER_FILE" | tr -d '\r' | tail -n 1)"

  if [ -z "$QUEUE_URL" ]; then
    echo "[!] Jenkins did not return a queue URL. Check Jenkins job history manually."
    return
  fi

  echo "[+] Jenkins queued build at $QUEUE_URL"
  BUILD_RESULT=""
  BUILD_API_URL=""

  for _ in $(seq 1 60); do
    QUEUE_JSON="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASS" "${QUEUE_URL}api/json" 2>/dev/null || true)"
    BUILD_API_URL="$(printf '%s' "$QUEUE_JSON" \
      | sed -n 's/.*"executable":{[^}]*"url":"\([^"]*\)".*/\1/p' \
      | sed 's#\\/#/#g')"

    if [ -n "$BUILD_API_URL" ]; then
      echo "[+] Jenkins build started: $BUILD_API_URL"
      break
    fi

    echo "    Jenkins build still queued..."
    sleep 2
  done

  if [ -z "$BUILD_API_URL" ]; then
    echo "[!] Jenkins build did not start in time."
    return
  fi

  for _ in $(seq 1 120); do
    BUILD_JSON="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASS" "${BUILD_API_URL}api/json" 2>/dev/null || true)"

    if printf '%s' "$BUILD_JSON" | grep -q '"building":false'; then
      BUILD_RESULT="$(printf '%s' "$BUILD_JSON" \
        | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"
      break
    fi

    echo "    Jenkins build still running..."
    sleep 2
  done

  if [ "$BUILD_RESULT" = "SUCCESS" ]; then
    echo "[+] Jenkins release sync completed successfully."
  else
    echo "[!] Jenkins release sync result: ${BUILD_RESULT:-unknown}"
    echo "[!] Last Jenkins console output:"
    curl -fsS -u "$JENKINS_USER:$JENKINS_PASS" "${BUILD_API_URL}consoleText" 2>/dev/null \
      | tail -n 120 || true
  fi
}

echo "[+] Gitea repositories initialization completed."

echo "[+] Seeding firmware repository from local Firmware directory..."

FIRMWARE_SRC="/seed/Firmware"
REPO_URL="https://devops-server:3000/$GITEA_OWNER/$FIRMWARE_REPO.git"
GITEA_GIT_BASIC_AUTH="$(printf '%s' "$GITEA_ADMIN:$GITEA_PASS" | base64 | tr -d '\n')"
WORKDIR="/tmp/firmware-robot-a"

if [ -d "$FIRMWARE_SRC" ]; then
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  unset GIT_DIR GIT_WORK_TREE

  echo "[+] Copying firmware files..."
  cp -a "$FIRMWARE_SRC/." "$WORKDIR/"

  seed_git() {
    git -c safe.directory="$WORKDIR" -C "$WORKDIR" "$@"
  }

  if [ ! -d "$WORKDIR/.git" ]; then
    git init --initial-branch=main "$WORKDIR"
  fi

  seed_git status --short >/dev/null
  seed_git branch -M main
  seed_git add .

  if seed_git diff --cached --quiet; then
    echo "[+] No firmware changes to commit."
  else
    seed_git \
      -c user.name="Gitea Init" \
      -c user.email="gitea-init@mecarobotix.local" \
      commit -m "Initial firmware import"
  fi

  if seed_git remote | grep -q "^origin$"; then
    seed_git remote set-url origin "$REPO_URL"
  else
    seed_git remote add origin "$REPO_URL"
  fi

  echo "[+] Pushing firmware repository to Gitea..."
  seed_git -c "http.extraHeader=Authorization: Basic ${GITEA_GIT_BASIC_AUTH}" push -u origin main || true

  echo "[+] Waiting for Gitea to expose branch main..."
  until curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
    "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/branches/main" >/dev/null 2>&1; do
    echo "    Branch main not visible through API yet..."
    sleep 2
  done

  echo "[+] Ensuring firmware release tag exists: $FIRMWARE_RELEASE_TAG"
  seed_git tag -f "$FIRMWARE_RELEASE_TAG"
  seed_git -c "http.extraHeader=Authorization: Basic ${GITEA_GIT_BASIC_AUTH}" push -f origin "$FIRMWARE_RELEASE_TAG" || true

  echo "[+] Firmware repository seeded successfully."

  echo "[+] Creating Gitea firmware release..."

  FIRMWARE_BUILD_DIR="$WORKDIR/.pio/build/esp32dev"
  FIRMWARE_ASSETS="firmware.bin firmware.elf"

  if [ -f "$FIRMWARE_BUILD_DIR/firmware.bin" ]; then
    RELEASE_JSON="$(curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
      "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/releases/tags/$FIRMWARE_RELEASE_TAG" 2>/dev/null || true)"

    if [ -n "$RELEASE_JSON" ]; then
      echo "[+] Gitea release already exists: $FIRMWARE_RELEASE_TAG"
    else
      RELEASE_RESPONSE="$(curl -sS -u "$GITEA_ADMIN:$GITEA_PASS" \
        -w '\n%{http_code}' \
        -X POST "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/releases" \
        -H "Content-Type: application/json" \
        -d "{\"tag_name\":\"$FIRMWARE_RELEASE_TAG\",\"target_commitish\":\"main\",\"name\":\"$FIRMWARE_RELEASE_NAME\",\"body\":\"Initial firmware release for Robot A.\",\"draft\":false,\"prerelease\":false}")"
      RELEASE_STATUS="$(printf '%s' "$RELEASE_RESPONSE" | tail -n 1)"
      RELEASE_JSON="$(printf '%s' "$RELEASE_RESPONSE" | sed '$d')"

      case "$RELEASE_STATUS" in
        2*)
          echo "[+] Gitea release created: $FIRMWARE_RELEASE_TAG"
          ;;
        *)
          echo "[!] Gitea release creation failed with HTTP $RELEASE_STATUS"
          echo "$RELEASE_JSON"
          RELEASE_JSON="$(curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
            "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/releases/tags/$FIRMWARE_RELEASE_TAG" 2>/dev/null || true)"
          ;;
      esac
    fi

    RELEASE_ID="$(printf '%s' "$RELEASE_JSON" \
      | grep -o '"id":[[:space:]]*[0-9][0-9]*' \
      | head -n 1 \
      | sed 's/[^0-9]//g')"

    if [ -z "$RELEASE_ID" ]; then
      echo "[!] Could not determine release ID for $FIRMWARE_RELEASE_TAG"
    else
      RELEASE_ASSETS="$(curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
        "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/releases/$RELEASE_ID/assets")"

      for ASSET_NAME in $FIRMWARE_ASSETS; do
        ASSET_PATH="$FIRMWARE_BUILD_DIR/$ASSET_NAME"

        if [ ! -f "$ASSET_PATH" ]; then
          echo "[!] Firmware release asset not found: $ASSET_PATH"
        elif printf '%s' "$RELEASE_ASSETS" | grep -q "\"name\":\"$ASSET_NAME\""; then
          echo "[+] Release asset already exists: $ASSET_NAME"
        else
          curl -fsS -u "$GITEA_ADMIN:$GITEA_PASS" \
            -X POST "$GITEA_URL/api/v1/repos/$GITEA_OWNER/$FIRMWARE_REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME" \
            -F "attachment=@$ASSET_PATH;filename=$ASSET_NAME" >/dev/null
          echo "[+] Uploaded release asset: $ASSET_NAME"
        fi
      done

      create_release_webhook "firmware-robot-a" "A" "robot-a-01"
      create_release_webhook "firmware-robot-b" "B" "robot-b-01"
      trigger_jenkins_release_sync "$FIRMWARE_REPO" "A" "robot-a-01" "$FIRMWARE_RELEASE_TAG"
    fi
  else
    echo "[!] Firmware binary not found: $FIRMWARE_BUILD_DIR/firmware.bin"
  fi
else
  echo "[!] Firmware source directory not found: $FIRMWARE_SRC"
fi
