set -x
WORKDIR=$1
SCRIPT=$2
ARGS=${@:3}
cd ${WORKDIR}
PYTHONPATH=/opt/openproblems:$PYTHONPATH python3 $SCRIPT ${ARGS}
