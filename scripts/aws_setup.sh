# TOKEN=ABC123QWERTY0987

sudo yum update
sudo yum install -y git-core
mkdir actions-runner && cd actions-runner
curl -O -L https://github.com/actions/runner/releases/download/v2.275.1/actions-runner-linux-x64-2.275.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.275.1.tar.gz
./config.sh --url https://github.com/singlecellopenproblems/SingleCellOpenProblems --token $TOKEN

AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
mkdir -p $AGENT_TOOLSDIRECTORY
sudo chown $USER $AGENT_TOOLSDIRECTORY
echo "AGENT_TOOLSDIRECTORY=$AGENT_TOOLSDIRECTORY" > .env

./run.sh
