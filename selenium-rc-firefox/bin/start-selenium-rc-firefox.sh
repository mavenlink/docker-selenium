#!/usr/bin/env bash

# set -e: exit asap if a command exits with a non-zero status
set -e

echoerr() { awk " BEGIN { print \"$@\" > \"/dev/fd/2\" }" ; }

# Wait for this process dependencies
timeout --foreground ${WAIT_TIMEOUT} wait-xvfb.sh
timeout --foreground ${WAIT_TIMEOUT} wait-xmanager.sh
timeout --foreground ${WAIT_TIMEOUT} wait-selenium-hub.sh

if [ "${USE_SELENIUM}" == "3" ]; then
  JAVA_OPTS="-Dwebdriver.gecko.driver=/usr/bin/geckodriver ${JAVA_OPTS}"
fi

JAVA_OPTS="$(java-dynamic-memory-opts.sh) ${JAVA_OPTS}"
echo "INFO: JAVA_OPTS are '${JAVA_OPTS}'"

# Add support for Selenium IDE exported scripts via `*chrome` https://github.com/SeleniumHQ/selenium/issues/2431
export FIREFOX_BROWSER_CAPS="browserName=*firefox,${COMMON_CAPS},version=${FIREFOX_VERSION},firefox_binary=${FIREFOX_DEST_BIN}"
java \
  ${JAVA_OPTS} \
  -jar ${SELENIUM_JAR_PATH} \
  -port ${SELENIUM_NODE_RC_FF_PORT} \
  -host ${SELENIUM_NODE_HOST} \
  -role rc \
  -hub "${SELENIUM_HUB_PROTO}://${SELENIUM_HUB_HOST}:${SELENIUM_HUB_PORT}/grid/register" \
  -browser "${FIREFOX_BROWSER_CAPS}" \
  -maxSession ${MAX_SESSIONS} \
  -timeout ${SEL_RELEASE_TIMEOUT_SECS} \
  -browserTimeout ${SEL_BROWSER_TIMEOUT_SECS} \
  -cleanUpCycle ${SEL_CLEANUPCYCLE_MS} \
  -nodePolling ${SEL_NODEPOLLING_MS} \
  -unregisterIfStillDownAfter ${SEL_UNREGISTER_IF_STILL_DOWN_AFTER} \
  ${SELENIUM_NODE_PARAMS} \
  ${CUSTOM_SELENIUM_NODE_PROXY_PARAMS} \
  ${CUSTOM_SELENIUM_NODE_REGISTER_CYCLE} \
  &
NODE_PID=$!

function shutdown {
  echo "-- INFO: Shutting down Firefox RC NODE gracefully..."
  kill -SIGINT ${NODE_PID} || true
  kill -SIGTERM ${NODE_PID} || true
  kill -SIGKILL ${NODE_PID} || true
  wait ${NODE_PID}
  echo "-- INFO: Firefox RC node shutdown complete."
  # First stop video recording because it needs some time to flush it
  supervisorctl -c /etc/supervisor/supervisord.conf stop video-rec || true
  killall supervisord
  exit 0
}

function trappedFn {
  echo "-- INFO: Trapped SIGTERM/SIGINT on Firefox RC NODE"
  shutdown
}
# Run function shutdown() when this process a killer signal
trap trappedFn SIGTERM SIGINT SIGKILL

# tells bash to wait until child processes have exited
wait ${NODE_PID}
echo "-- INFO: Passed after wait java Firefox RC node"

# Always shutdown if the node dies
shutdown

# Note to double pipe output and keep this process logs add at the end:
#  2>&1 | tee $SELENIUM_LOG
# But is no longer required because individual logs are maintained by
# supervisord right now.
