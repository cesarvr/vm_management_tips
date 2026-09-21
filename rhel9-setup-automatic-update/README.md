## Automatic Updates Setup 

This playbook:
- Configures `dnf-automatic` package to configure `security only` automatic updates.
- Setup the a systemd timer to trigger the update.  
- Configure the trigger for the third weekend of the month. 
- Make sure that changes are applied. 


```sh
    ansible-playbook -i inventory.ini setup-automatic-updates.yml
```



