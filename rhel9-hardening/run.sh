podman run --rm -it \
  --net=host \
  -e ANSIBLE_HOST_KEY_CHECKING=False \
  -v $(pwd):/workdir:Z \
  -w /workdir \
  registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:2.16 \
  bash -c "ansible-galaxy role install ansible-lockdown.rhel9_cis && \
           ansible-galaxy collection install community.general ansible.posix && \
           ansible-playbook -i inventory.ini -k --ask-become-pass cis_level_one.yml"
