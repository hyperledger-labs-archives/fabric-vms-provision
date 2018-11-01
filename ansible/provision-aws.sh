#!/bin/bash

date

set -x
set -e

rm -rf ~/.ssh/known_hosts


PEER_COUNT=$@
export VARS_FILE=./vars/aws.yml

# autogenerate the role for creating the softlayer vms
python3 utils/aws/aws.py  -p $PEER_COUNT  >  roles/create/tasks/main.yml

ansible-playbook create.yml

sleep 20

# autogenerate the ansible hosts file
python3 utils/aws/ans_hosts.py > hosts

# autogenerate a /etc/hosts file, to be included in each softlayer vm
python3 utils/aws/etc_hosts.py > roles/common/files/hosts


eval `ssh-agent`

ansible-playbook  --key-file "~/.ssh/fabric"  root.yml
ansible-playbook  --key-file "~/.ssh/fabric"  common.yml
ansible-playbook  --key-file "~/.ssh/fabric"  --extra-vars "peer_count=\"$PEER_COUNT\""  build.yml


# autogenerate each playbook for packaging each fabric component, peerXorgY, ordererY, etc
python3 utils/package.py  -p $PEER_COUNT  -v $VARS_FILE

# autogenerate each playbook for starting (via systemd) each fabric component
python3 utils/start.py  -p $PEER_COUNT  -v $VARS_FILE


ssh-add ~/.ssh/fabric

# call each autogenerated ansible playbook for packaging each fabric component
./autogen_package.sh

# call each autogenerated ansible playbook for starting each fabric component
./autogen_start.sh


cat << 'EOF' > cancel.yml
---
- hosts: localhost
  gather_facts: False
  vars_files:
  - "{{ lookup('env','VARS_FILE') }}"
  tasks:
  - name: Gather EC2 facts
    ec2_instance_facts:
      filters:
        "tag:Class": fabric
        instance-state-name: running
    register: facts

  - debug: var=facts

  - ec2:
      state: absent
      region: "{{ region }}"
      instance_ids: "{{ item.instance_id }}"
    with_items: "{{ facts.instances }}"
EOF


date