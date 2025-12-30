FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    ANSIBLE_FORCE_COLOR=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        git \
        ca-certificates \
        bash \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip && \
    pip install "ansible" "ansible-lint" "jinja2" "pyyaml"

RUN useradd -m -u 1000 ansible
USER ansible
WORKDIR /home/ansible

RUN mkdir -p /home/ansible/workdir /home/ansible/.ssh
VOLUME ["/home/ansible/workdir"]

ENTRYPOINT ["sleep", "infinity"]