#!/bin/base
set -e

################################################################################
# DEFAULT CONFIGURATION                                                                #
################################################################################
SCRIPT_DIR=$(cd $(dirname $0) && pwd)
SCRIPT_NAME=$(basename $0)
BASE_DIR=$(cd $SCRIPT_DIR/.. && pwd)
INTERACTIVE_MODE=true
BUILD_ONLY=false # Changed with flav -b
REBUILD=false # Changed with flag -r
INSTALL_SSO=false # Changed with --install-sso

function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
}

function pre_checks() {
  oc status >/dev/null 2>&1 || { echo >&2  "You are not connected to OCP cluster, please login using oc login ... before running $SCRIPT_NAME!"; exit 1; }
  mvn -v -q >/dev/null 2>&1 || { echo >&2 "Maven is required but not installed yet... aborting."; exit 2; }
  oc version | grep openshift | grep -q "v3\.[4-9]" || { echo >&2 "Only OpenShift Container Platfrom 3.4 or later is supported"; exit 3; }
}

function init() {
  
  OPENSHIFT_MASTER=$(oc status | head -1 | sed 's#.*\(https://[^ ]*\)#\1#g') # must run after projects are created
  OPENSHIFT_PROJECT=$(oc project | head -1 | sed 's#Using project "\(.*\)" on server.*#\1#g')

  if [ -z "$HOST_SUFFIX" ]; then
    oc create route edge testroute --service=testsvc --port=80 >/dev/null
    HOST_SUFFIX=$(oc get route testroute -o template --template='{{.spec.host}}' | sed "s/testroute-//g")
    DOMAIN=$(oc get route testroute -o template --template='{{.spec.host}}' | sed "s/testroute-${OPENSHIFT_PROJECT}.//g")
    oc delete route testroute > /dev/null  
  fi

  if [ -z "${COOLSTORE_GW_ENDPOINT}" ] && [ -z "${MODULE_NAME}" ];  then
    COOLSTORE_GW_ENDPOINT="http://gateway-${HOST_SUFFIX}"
  fi

  if [ -z "${SSO_URL}" ]; then
    if ${INSTALL_SSO}; then
      SSO_URL="http://sso-${HOST_SUFFIX}"
    fi
  fi

}

function wait_while_empty() {
  local _NAME=$1
  local _TIMEOUT=$(($2/5))
  local _CONDITION=$3

  echo "Waiting for $_NAME to be ready..."
  local x=1
  while [ -z "$(eval ${_CONDITION})" ]
  do
    echo "."
    sleep 5
    x=$(( $x + 1 ))
    if [ $x -gt $_TIMEOUT ]
    then
      echo "$_NAME still not ready, I GIVE UP!"
      exit 255
    fi
  done

  echo "$_NAME is ready."
}

function print_info() {
  echo "OpenShift Master:    ${OPENSHIFT_MASTER}"
  echo "OpenShift Project:   ${OPENSHIFT_PROJECT}"
  echo "Demo Module          ${MODULE_NAME:-N/A}"
  echo "Domain:              ${DOMAIN}"
  echo "Host suffix:         ${HOST_SUFFIX}"
  echo "Interactive mode:    ${INTERACTIVE_MODE}"
  echo "Build only mode:     ${BUILD_ONLY}"
  echo "Rebuild:             ${REBUILD}"
  echo "Script name:         ${SCRIPT_NAME}"
  echo "Script directory:    ${SCRIPT_DIR}"
  if [ ! -z "${COOLSTORE_GW_ENDPOINT}" ]; then
    echo "Coolstore GW:        ${COOLSTORE_GW_ENDPOINT}"
  fi
  if [ ! -z "${SSO_URL}" ]; then
    echo "SSO URL              ${SSO_URL}"
  fi

  if $INTERACTIVE_MODE; then
    read -p 'Is this correct (y/N): ' correct
    if [ "$correct" != "" ]; then
      if [[ ${correct} =~ ^[Y|y] ]]; then 
        return
      fi
    fi
    echo "User selected to abort"
    exit
  fi
}

function usage() {
  echo "Usage:"
  echo " $SCRIPT_NAME <parameters>"
  echo ""
  echo "Available parameters:"
  echo ""
  echo "  -h, --help Prints this dialog"
  echo "  -i, --interactive=false The script will not ask for input and will run with default values unless other values are specified as parameters"
  if [ "$MODULE_NAME" == "web-ui" ]; then  # The --gateway flag is only available for the web-ui module
    echo "  -g [url], --gateway==[url] Set the coolstore gateway"
  fi
  if [ "$MODULE_NAME" == "web-ui" ] || [ "$MODULE_NAME" == "gateway" ]; then  # The --sso=[url] parameter is only available for the web-ui and gateway module
    echo "  -s [url], sso=[url] The url to the Red Hat SSO service if already installed"
    fi
  if [ -z "$MODULE_NAME" ]; then  # the --install-sso parameter is only available for install scripts and not for individual modules
    echo "  --install-sso Set this flag to install sso"
  fi
}

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        -i|--interactive)
            INTERACTIVE_MODE=false
            if [ "$VALUE" == "true" ]; then
                INTERACTIVE_MODE=true
            fi
            ;;
        -r|--rebuild)
            REBUILD=true
            if [ "$VALUE" == "false" ]; then
                REBUILD=false
            fi
            ;;
        -g|--gateway)
            if [ "$VALUE" == "" ]; then
              shift # past argument
              COOLSTORE_GW_ENDPOINT=$1
              if [ "$COOLSTORE_GW_ENDPOINT" == "" ]; then
                echo "Parameter -g, --gateway requires a valuye containing a endpoint URL"
                exit 1
              fi
            else
              COOLSTORE_GW_ENDPOINT=$VALUE
            fi
            ;;
        -s|--sso)
            if [ "$VALUE" == "" ]; then
              shift # past argument
              SSO_URL=$1
              if [ "$SSO_URL" == "" ]; then
                echo "Parameter -s, --sso requires a value containing a SSO URL"
                exit 1
              fi
            else
              SSO_URL=$VALUE
            fi
            ;;
        --install-sso)
            INSTALL_SSO=true
            if [ "$VALUE" == "false" ]; then
                INSTALL_SSO=false
            fi
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

echo_header "Running pre-checks...."
pre_checks

echo_header "Initialize the settings"
init

echo_header "Configuration"
print_info