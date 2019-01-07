#!/usr/bin/env sh

set -x

SERVICE=condenser

[ ! -z ${CONDENSER_USER} ] || CONDENSER_USER="${SERVICE}d"
[ ! -z ${CONDENSER_HOME} ] || CONDENSER_HOME="/usr/local/${SERVICE}d"
[ ! -z ${CONDENSER_PORT} ] || CONDENSER_PORT=8080
[ ! -z ${CONDENSER_DOCKER_HOST} ] || CONDENSER_DOCKER_HOST=unix:///var/run/docker.sock

WORKTREE="`dirname \`realpath ${0}\``"
SERVICE_REPO="${SUDO_USER}/${PROJECT}_${SERVICE}"
STAGE0="${SERVICE_REPO}_stage0"
CONDENSER_GIT_TAG="`cd ${WORKTREE} && git describe --long --tags --dirty`"
STAGE1="${SERVICE_REPO}:${CONDENSER_GIT_TAG}"
STAGE_LATEST="${SERVICE_REPO}:latest"
DIRTY="`cd ${WORKTREE} && git status -s`"

mkdir -p \
    "${WORKTREE}/node_modules" \
    "${WORKTREE}/dist" \
    "${WORKTREE}/tmp" \
    "${WORKTREE}/lib" && \
chown \
    -R \
    "${SUDO_UID}:${SUDO_GID}" \
    "${WORKTREE}/node_modules" \
    "${WORKTREE}/dist" \
    "${WORKTREE}/tmp" \
    "${WORKTREE}/lib" && \
([ -z "${DIRTY}" ] && buildah inspect "${STAGE1}" > /dev/null 2> /dev/null || \
 (buildah inspect "${STAGE0}" > /dev/null 2> /dev/null || \
  buildah from \
      --name "${STAGE0}" \
      node:8.7-stretch) && \
 buildah config \
     -e CONDENSER_GIT_TAG="${CONDENSER_GIT_TAG}" \
     -u root \
     --workingdir "${WORKTREE}" \
     "${STAGE0}" && \
 buildah run \
     "${STAGE0}" \
     /usr/bin/env \
         -u USER \
         -u HOME \
         sh -c -- \
            "apt update && \
             apt upgrade -y" && \
 buildah run \
     --user "${SUDO_UID}:${SUDO_GID}" \
     -v "${WORKTREE}/package.json:/usr/src/${SERVICE}/package.json:ro" \
     -v "${WORKTREE}/yarn.lock:/usr/src/${SERVICE}/yarn.lock:ro" \
     -v "${WORKTREE}/node_modules:/usr/src/${SERVICE}/node_modules" \
     "${STAGE0}" \
     /usr/bin/env \
         -u USER \
         -u HOME \
         sh -c -- \
            "cd \"/usr/src/${SERVICE}\" && \
             NODE_ENV=development \
             yarn install \
                 --non-interactive \
                 --pure-lockfile" && \
 buildah run \
     --user "${SUDO_UID}:${SUDO_GID}" \
     -v "${WORKTREE}:/usr/src/${SERVICE}:ro" \
     -v "${WORKTREE}/node_modules/:/usr/src/${SERVICE}/node_modules" \
     -v "${WORKTREE}/dist:/usr/src/${SERVICE}/dist" \
     -v "${WORKTREE}/tmp:/usr/src/${SERVICE}/tmp" \
     -v "${WORKTREE}/lib:/usr/src/${SERVICE}/lib" \
     "${STAGE0}" \
     /usr/bin/env \
         -u USER \
         -u HOME \
         sh -c -- \
            "cd \"/usr/src/${SERVICE}\" && \
             rm -rf ./dist/* && \
             yarn run build" && \
 buildah run \
     -v "${WORKTREE}:/usr/src/${SERVICE}:ro" \
     "${STAGE0}" \
     /usr/bin/env \
         -u USER \
         -u HOME \
         sh -c -- \
            "adduser \
                 --system \
                 --home \"${CONDENSER_HOME}\" \
                 --shell /bin/bash \
                 --group \
                 --disabled-password \
                 \"${CONDENSER_USER}\" && \
             rm -rf \"${CONDENSER_HOME}\" && \
             cp \
                 -PRT \
                 \"/usr/src/${SERVICE}\" \
                 \"${CONDENSER_HOME}\"" && \
 buildah config \
     -e USER="${CONDENSER_USER}" \
     -e HOME="${CONDENSER_HOME}" \
     -e PORT="${CONDENSER_PORT}" \
     --cmd "yarn run production" \
     -p "${CONDENSER_PORT}" \
     -p "`echo \"${CONDENSER_PORT} + 1\" | bc`" \
     -u "${CONDENSER_USER}" \
     --workingdir "${CONDENSER_HOME}" \
     "${STAGE0}" && \
 buildah commit \
     "${STAGE0}" \
     "${STAGE1}" &&
 buildah tag \
     "${STAGE1}" \
     "${STAGE_LATEST}" &&
 buildah push \
     --dest-daemon-host "${CONDENSER_DOCKER_HOST}" \
     "${STAGE1}" \
     "docker-daemon:${STAGE1}" &&
 docker \
     -H "${CONDENSER_DOCKER_HOST}" \
     tag \
         "${STAGE1}" \
         "${STAGE_LATEST}")
