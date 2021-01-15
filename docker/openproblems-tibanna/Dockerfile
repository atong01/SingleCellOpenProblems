FROM singlecellopenproblems/openproblems:latest

# Install Docker
RUN apt-get update
RUN apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common sudo
RUN curl -fsSL https://download.docker.com/linux/debian/gpg > key.gpg
RUN apt-key add key.gpg
RUN apt-key fingerprint 0EBFCD88

RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
RUN apt-get update
RUN apt-get install -y docker-ce docker-ce-cli containerd.io
RUN systemctl enable docker

# Install Python packages
COPY ./docker/openproblems-tibanna/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
