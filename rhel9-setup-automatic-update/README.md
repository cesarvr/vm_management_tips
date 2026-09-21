## Automatic Updates Setup 

This playbook:
- Configures `dnf-automatic` package to configure `security only` automatic updates.
- After update it setups the machine for restart *if required*. 
- Setup the a systemd timer to trigger the update.  
- Configure the trigger for the third weekend of the month. 
- Make sure that changes are applied. 

### Running 

Check the hosts. 
```sh 
ansible rhel9_cluster -i inventory.ini -m ping   
```

> If everything goes well, then: 


```sh
    ansible-playbook -i inventory.ini setup-automatic-updates.yml
```

> All host should be configure with automatic update.

