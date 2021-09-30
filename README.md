__Dump and Restore Metastore Database to new RDS Instance__

To migrate a PostgreSQL database from a Kubernetes pod to an RDS instance the script named `migrate.sh` performs a pg_dump on the existing database and restores the plain SQL restore file to a new RDS instance. To run this script use the command:

```bash
./migrate.sh <pod-addr> <db-name> <db-user> <pwd-path>
``` 
where the values pod-addr, db-name, db-user and pwd-path refer to the location of the existing pod, the username to connect with, database name to acces and a password (which can also be provided as a password file location) respectively.

__Initialise RDS Database__

The migrate script as part of its operation initialises a a new RDS database for by calling a second script `build.sh`. This script takes the existing database name and user when creating a new RDS instance to minimise transition effort and also reads a password path as a location to store a newly generated random password. The format for this command is;

```bash
./build.sh <db-name> <db-user> <pwd-path>
```

If arguments are not provided, default values will return a database name *RDS_DATA* accessible by a the user *vp_user*.

__Clean RDS+__

To remove the security group, subnet group and RDS database created during build the `clean.sh` script reads the identities of these elements and attempts to delete them from aws. 

```bash
./clean.sh [ <rds_db_id> <sng-name> <sg-name> ]
```

The arguments identify the RDS instance ID, the subnet group and the security group. They are optional because these values are stored in the refs file and will be imported if not provided

__Setup Metastore and Trino__

The script `meta.sh` runs a helm install that sets up one metastore instance, a trino coordinator and up to four trino workers. This script is called by the `migrate.sh` during a full run

```bash
./meta.sh [ <rds-host> <rds-password-path> ]
```

__Testing__

Unittesting is done using python unittest. Tests are collected in a suite called `test_migration.py` which can be run with the command.

```python
python test_migration.py
```

Testing will run a range of simple tests on the data returned after the migration and will operate on both the previous and new implementations. This will pick up any discrepencies in the returned data.


__HACK - postgres user__

By default super user access is not provided on container object database instances for security reasons. In practise, in order to dump a database for migration, we must run the `pg_dump` command as a privileged user. One process to achieve this required level of access is outlined here.  

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