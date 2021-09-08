__Instantiate RDS Database__

To build an RDS postgresql instance on AWS run the included build.sh script

__HACK - postgres user__

1. Install jordanwilson230's kubectl plugin for ssh

https://github.com/jordanwilson230/kubectl-plugins

2. Login to pod
```bash
kubectl ssh -u root <your-pod>`
```

3. Add postgres user
```bash
adduser postgres
```

4. Install an editor
```bash
apt-get update
apt-get install vim
```

5. Edit pg_hba.conf
```bash
cat /opt/bitnami/postgresql/conf/pg_hba.conf
local   all   all   trust
...
```
6. Bump postgres (needs to be done as 1001)
```bash
kubectl -it exec ... /bin/bash
pg_ctl reload
```

7. su to postgres and login
```bash
su postgres
psql metastore
```

8. Give your dump user superuser
```sql
metastore=# alter user metastore_user with superuser;
ALTER ROLE
metastore=# \du
List of roles
Role name       | Attributes            | Member of 
----------------+-----------------------+-----------
 metastore_user | Superuser, Create DB  | {}
 postgres       | Superuser, Create ... | {}
 ```

Now you should be able to run the dump without access errors