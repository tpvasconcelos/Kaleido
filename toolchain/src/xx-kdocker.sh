#!/bin/bash
set -e
set -u

# Please do your flags first so that utilities uses $NO_VERBOSE, otherwise failure!

IMAGE="cimg/python:3.12.3"
usage=(
  "kdocker is convenience script to start dockers for building on linux."
  ""
  "You need to be in the docker group to run kdocker. kdocker 1) pulls an image 2) adds"
  "the user who ran kdocker, 3) mounts the project directory to /usr/share/kaleido."
  "See bottom for tips on detaching and reattaching to the docker."
  ""
  "Usage (DO NOT USE --long-flags=something, just --long-flag something):"
  "You can always try -v or --verbose"
  ""
  "Display this help:"
  "kdocker [-h|--h]"
  ""
  "kdocker [-u USER] [-i|--image IMAGE] [-d|--detach] COMMAND"
  ""
  "-u|--user USER     If you are running kdocker as sudo, you can use this to specify which"
  "                   user you normally are."
  ""
  "-i|--image IMAGE   IMAGE will be used instead of the default, $IMAGE."
  "                   If this is not the same as circle-ci, please submit a pull request"
  "                   updating this script"
  ""
  "-d|--detach        This will run the container and immediately detach."
  "                   The container will also exit immediately after finishing."
  ""
  "-c|--copy          This will reclone your git project to ~/kaleido and also patch over"
  "                   all uncommited, staged and unstaged, tracked changes. Untracked changes"
  "                   will not be cloned over. "
  "                   Hint: Use \`git add -N PATH\` to track files without staging them for commit."
  "                   Hint: Don't work out of the clone ~/kaleido directory."
  "                   Hint: Use \`refresh\` to re-clone/patch ~/kaleido after changes."
  "                   Hint: If you use -c (or `refresh`), kaleido build commands (set_version, etc)"
  "                         will always be run from ~/kaleido, not /usr/share/kaleido."
  "Docker tips:"
  "      Ending the first session will always end the docker. \`ctl+d\` will exit bash and session."
  "     \`ctl+p ctl+q\` (instead of \`ctl+d\`) will leave bash running. You can reattach to (only)"
  "      the first session with: \`docker attach CONTAINER_NAME\`. Containers can be listed with"
  "     \`docker container ls\`. You can get a new secondary session with:"
  "     \`docker exec --user \$USER -it CONTAINER_NAME bash\`."
)

## PROCESS FLAGS
DETACH=""
NO_VERBOSE=true
COPY=false
LOCAL_USER="$USER"
while (( $# )); do
  case $1 in
    -h|--help)        printf "%s\n" "${usage[@]}"; exit 0  ;;
    -i|--image)       shift; IMAGE="$1"                    ;;
    -u|--user)        shift; LOCAL_USER="$1"               ;;
    -d|--detach)      DETACH="d"                           ;;
    -v|--verbose)     NO_VERBOSE=false                     ;;
    -c|--copy)        COPY=true                            ;;
    *)                break                                ;;
  esac
  shift
done
LOCAL_UID="$(id -u $LOCAL_USER)"
COMMAND="true || sudo apt-get update; sudo useradd --uid=$LOCAL_UID --shell /bin/bash --create-home $LOCAL_USER; echo '$LOCAL_USER ALL=NOPASSWD: ALL' | sudo tee -a /etc/sudoers.d/50-circleci &> /dev/null;"
USER_COMMAND=''

$NO_VERBOSE || echo "Running xx-kdocker.sh"

SCRIPT_DIR=$( cd -- "$( dirname -- $(readlink -f -- "${BASH_SOURCE[0]}") )" &> /dev/null && pwd )
. "$SCRIPT_DIR/include/utilities.sh"

VOLUME="$MAIN_DIR:/usr/share/kaleido"
if [[ -n "${@}" ]]; then
  USER_COMMAND+="${@}; "
fi

SUDO="sudo sudo -u $LOCAL_USER"
_OUT="1> /dev/null"
BASH_LOGIN="/home/$LOCAL_USER/.bash_login"
TEMP_SCRIPT="/home/$LOCAL_USER/.temp_script.sh"
COMMAND+="\
  echo '$USER_COMMAND' | $SUDO tee -a $TEMP_SCRIPT $_OUT; \
  echo . $TEMP_SCRIPT | $SUDO tee -a $BASH_LOGIN $_OUT; \
  echo 'rm -f $TEMP_SCRIPT' | $SUDO tee -a $BASH_LOGIN $_OUT; \
  echo 'head -n -3 $BASH_LOGIN > $BASH_LOGIN' | $SUDO tee -a $BASH_LOGIN $_OUT; "
if $COPY; then
  COMMAND+="$SUDO -- git clone /usr/share/kaleido /home/$LOCAL_USER/kaleido; \
    $SUDO git -C /usr/share/kaleido diff -p HEAD | $SUDO tee /home/$LOCAL_USER/.git_patch_1 $_OUT; \
    $SUDO git -C /home/$LOCAL_USER/kaleido apply /home/$LOCAL_USER/.git_patch_1; "
fi
COMMAND+="sudo su - $LOCAL_USER"

docker pull $IMAGE
docker container run -e TERM=$TERM --rm -it$DETACH -v "$VOLUME" "$IMAGE" bash -c "$COMMAND"