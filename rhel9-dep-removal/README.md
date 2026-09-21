## Dependencies Removal 

A example on how to automate dependencies removal from VM's.

### Running 

Check the hosts. 
```sh 
ansible rhel9_cluster -i inventory.ini -m ping   
```

If everything is fine, then: 


```sh
 ansible-playbook -i inventory.ini dep-removal.yml -K 
```



