Opencart 3.0.3.2
========
powered by Apache 2, PHP7.3-apache, MySQL 8.0


[OpenCart][1] is designed feature rich, easy to use, search engine
friendly and with a visually appealing interface.

Instructions for Composer
========

```
1) $ curl -sSL https://raw.githubusercontent.com/aam-git/dockerfiles/master/opencart/docker-compose.yml > docker-compose.yml
2) use your text editor to edit docker-compose.yml (eg nano docker-compose.yml) and enter a more secure MYSQL_ROOT_PASSWORD
3) $ docker-compose up -d
4) go to your web url (eg. http://127.0.0.1)
5) go through the opencart standard install procedure
 - DB Driver is "MySQLi"
 - Hostname is "mysql"
 - Username is "root"
 - Password is "secure_password_here" (though you should have changed this in step 2)
 - Database is "opencart"
 - Enter your own details for step 2
6) Opencart Install should now be complete, you can now delete the install folder.
7) Log into admin, in the popup for Storage location, change it to anywhere under "/var/www/" for example "/var/www/storage"
```

Please note this is not fully tested yet, so please make sure to fully test everything before taking it into a production environment.

I'll be updating it over the coming weeks if needs be.

## docker-compose.yml

```yaml
version: '3.2'
services:
  mysql:
    image: mysql:8.0
    container_name: mysql
    hostname: mysql
    command: --default-authentication-plugin=mysql_native_password
    environment:
      - MYSQL_DATABASE=opencart
      - MYSQL_ROOT_PASSWORD=change_to_secure_password
    restart: always
    volumes:
      - mysql_data:/var/lib/mysql
  opencart:
    image: aamservices/opencart:latest
    container_name: opencart
    hostname: opencart
    restart: always
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - opencart_html:/var/www
    depends_on:
      - mysql
volumes:
  mysql_data:
    driver: local
  opencart_html:
    driver: local
```


[1]: http://www.opencart.com/index.php
