## READ ME BEFORE RUNNING ##

The scripts contained here irreversably alter the data within the `cru_revision` and `cru_stored_path` tables, and also updates any dependencies pointed to records within those tables. For this reason it is ***highly recommended*** that your team thoroughly test running these scripts in a **non-production** Fisheye/Crucible environment first, and that a backup is taken of the environment (including the external database _AND_ your Fisheye instance's `config.xml` file) prior to running these scripts on **any** environment.

Your team should aim to ensure:

1. You are able to successfully execute the entire script without error
2. The upgrade to 4.8.0+ completes successfully, and that the environment can be started without issue following the upgrade
3. The data contained within your Crucible reports renders correctly, and that there are no clear data issues

After confirming the above results, it's only at that point that your team should construct a maintenance plan to run this script against your production environment as part of the 4.8.0+ upgrade process.

### Purpose ###

These scripts are intended to address the situation where, when upgrading to Fisheye/Crucible 4.8.0 or later, the following type of error prevents the upgrade from working as expected:

```
2020-08-18 12:30:42,998 ERROR - The Web context could not be started
org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'dbControlFactory' defined in ServletContext resource [/WEB-INF/applicationContext.xml]: Instantiation of bean failed; nested exception is org.springframework.beans.BeanInstantiationException: Could not instantiate bean class [com.cenqua.crucible.hibernate.DBControlFactoryImpl]: Constructor threw exception; nested exception is com.cenqua.crucible.hibernate.CruDBException: Problem upgrading database
...
Caused by: com.cenqua.crucible.hibernate.CruDBException: Problem upgrading database
...
Caused by: java.sql.SQLIntegrityConstraintViolationException: ORA-00001: unique constraint (FISHEYE_OWNER.UK_SOURCE_REV_PATH_HASH) violated
```

### What exactly does this script do? ###

Identifies and removes any duplicate records in cru_stored_path, and then re-points any cru_revision records pointing to the dupes.   

Then identifies any subsequent duplicates in cru_revision from this re-pointing, re-points THOSE dependencies, and then removes any duplicate records in cru_revision.   

Lastly - re-calculates the hash data in cru_stored_path.cru_hash.

### Available database types ###

- MSSQL
- Oracle 12c
- PostgreSQL
- MySQL

### Support ###

These scripts are only expected to act as an example of how to repair any duplicate records
