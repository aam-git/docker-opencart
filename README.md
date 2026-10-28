# OpenCart Docker Container

[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![OpenCart](https://img.shields.io/badge/OpenCart-3.0.5.1-blue?style=for-the-badge)](https://www.opencart.com/)
[![PHP](https://img.shields.io/badge/PHP-8.4--apache-777BB4?style=for-the-badge&logo=php&logoColor=white)](https://php.net/)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://mysql.com/)

A production-ready, fully automated Docker setup for the [OpenCart](https://www.opencart.com/) e-commerce platform. It installs a new shop on first start, and it upgrades an existing 3.0.3 or 3.0.4 shop when you change the image tag. Your compose file, configuration, and uploaded files stay in place.

The image is published as `ghcr.io/aam-git/docker-opencart:3.0.5.1`. This branch is not tagged `latest`. A stack that tracks `latest` stays on that other image until you point it here on purpose.

## ✨ Features

- **🚀 Fully Automated Installation** - Zero manual configuration required
- **🔒 Security-First Design** - Enforced password validation and secure defaults
- **🐳 Multi-Container Architecture** - Separate database and application containers
- **⚙️ Comprehensive Configuration** - 15+ environment variables for complete customisation
- **🌍 Multi-Language Support** - Further languages are added from the OpenCart admin after installation
- **🏪 Multi-Store Ready** - Configurable table prefixes for multiple stores
- **🔄 Version Agnostic** - The same image installs 3.0.5.1, or upgrades a 3.0.3 or 3.0.4 shop
- **🛡️ Production Ready** - Optimised for both development and production environments
- **💾 Persistent Data** - Docker volumes ensure data persistence across container restarts
- **🔧 Flexible Database Options** - Support for MySQL, Percona, and MariaDB with multiple drivers

## 🚀 Quick Start

Get your OpenCart store running in under 2 minutes:

```bash
# Download configuration files
curl -sSL https://raw.githubusercontent.com/aam-git/docker-opencart/3.0.5.1/docker-compose.yml > docker-compose.yml
curl -sSL https://raw.githubusercontent.com/aam-git/docker-opencart/3.0.5.1/.env.example > .env

# Configure your environment (edit passwords, email, etc.)
nano .env

# Deploy your store
docker compose up -d
```

The store is then at [http://localhost](http://localhost). The admin is at [http://localhost/admin](http://localhost/admin).

The sample compose file names the database service `mysql`, mounts the shop at `/var/www`, and uses MySQL 8.0. Set `MYSQL_IMAGE=percona:8` when you want Percona instead. MySQL is published on `127.0.0.1` only.

With the admin username, password, email, and the `DB_*` variables set, the container installs the shop for you. Without those variables it leaves the web installer in place.

## Upgrade an existing shop

Keep the compose file you already run. Change only the OpenCart image to `ghcr.io/aam-git/docker-opencart:3.0.5.1`.

Leave these as they are:

- The app volume, mounted at `/var/www`
- The database service. The hostname is read from `config.php`, so `mysql` and `database` both work
- Traefik, or whichever proxy terminates TLS and routes to port 80
- `PHP_MEMORY_LIMIT`, including a value such as `2G`

MySQL 8 and Percona 8 with `mysql_native_password` both work. Keep the database server that shop already uses. Do not mount an existing 8.0 data directory onto MySQL 9.

On the first start the container:

1. Copies the 3.0.5.1 core files over the shop. Extension files, vQmod, `config.php`, the admin `config.php`, and `image/` stay in place. A renamed admin directory, such as `shopadmin`, is read from that admin `config.php` and the new admin files are copied there.
2. Leaves storage uploads, downloads, sessions, and logs in place.
3. Writes a SQL dump into the storage `backup/` directory when it can.
4. Upgrades the database schema once. Config files are restored if an upgrade model changes them.
5. Clears `cache/` and `modification/`, then removes `install/` when the upgrade succeeds.
6. Modifications that are enabled are recorded, switched off for the schema upgrade, and switched back on afterwards.
7. Adds the PHP 8 repair modification when its code is not already present, and updates it when the image has a newer version. An older image leaves a newer installed repair in place.

Take your own backup of the database before that first start. After the shop is up, open Extensions, then Modifications, and refresh so the repair and your other extensions are compiled.

## ⚙️ Configuration

### Environment Variables

All configuration is managed through environment variables in your `.env` file. The sample file has usable defaults. Change the passwords and the admin email before you rely on a new shop.

An existing shop does not need these variables. Its `config.php` is used as it stands.

#### 🔐 Required for a new command-line install

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DB_PASSWORD` | Database root password | `please_change_this_password` | Yes |
| `OPENCART_PASSWORD` | Admin account password | `please_change_this_password` | Yes |
| `OPENCART_EMAIL` | Admin email address | `admin@example.com` | Yes |

`DB_HOSTNAME`, `DB_USERNAME`, `DB_DATABASE`, and `OPENCART_USERNAME` are also needed before the command-line installer runs. The sample compose file supplies defaults for those. If the admin email, password, or database settings are missing, and the volume is empty, the container starts the web installer.

A new command-line install is refused when either password is shorter than 8 characters, or is `password`, `123456`, `admin`, `root`, or `test`.

#### 🐳 Container Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `MYSQL_IMAGE` | Database image. `percona:8` is supported. | `mysql:8.0` |
| `OPENCART_IMAGE` | OpenCart image | `ghcr.io/aam-git/docker-opencart:3.0.5.1` |
| `HTTP_PORT` | Host port published to container port 80 | `80` |
| `MYSQL_PORT` | Host port published to MySQL on localhost | `3306` |

TLS belongs on your reverse proxy. The container serves HTTP. Port 443 is exposed for that proxy and is not configured with a certificate.

#### 🗄️ Database Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOSTNAME` | Database hostname. This is the compose service name. | `mysql` |
| `DB_PORT` | Database port | `3306` |
| `DB_DATABASE` | Database name | `opencart` |
| `DB_USERNAME` | Database username | `root` |
| `DB_DRIVER` | Database driver (`mysqli` or `pdo`) | `mysqli` |
| `DB_PREFIX` | Database table prefix | `oc_` |

On an existing shop these values are read from `config.php`.

#### 🏪 Store Configuration

Used for a new command-line install. The first name, last name, and store name are optional. Leave one unset and that field stays as the installer wrote it. You can set any one of them on its own.

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCART_USERNAME` | Admin username | `admin` |
| `OPENCART_FIRSTNAME` | Admin first name | unset, optional |
| `OPENCART_LASTNAME` | Admin last name | unset, optional |
| `OPENCART_SITE_NAME` | Store name and browser title | unset, optional |
| `OPENCART_SITE_URL` | Store URL | `http://localhost` |

`OPENCART_SITE_URL` is written into the shop URL only during a command-line install. An existing shop keeps the addresses already stored in `config.php`.

#### ⚡ PHP Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `PHP_MEMORY_LIMIT` | PHP memory limit | `256M` |
| `PHP_MAX_EXECUTION_TIME` | Script execution timeout, in seconds | `300` |
| `PHP_UPLOAD_MAX_FILESIZE` | Maximum upload size | `64M` |
| `PHP_POST_MAX_SIZE` | Maximum form post size. Keep this at least as large as the upload limit. | `64M` |
| `TZ` | PHP timezone | `UTC` |

OPcache checks file timestamps on every request. A changed PHP file, including one saved over SFTP, is compiled again on the next request. Refreshing or clearing modifications still drops the whole cache.

> **📋 Complete reference**: see `.env.example` for the same settings with short comments.

## 🔄 Automated Installation Process

The container does this on startup:

1. **🔍 Environment and PHP**
   - Writes the PHP limits from the variables above, including `PHP_MEMORY_LIMIT`
   - For a new command-line install, checks that the passwords are long enough and are not weak

2. **🗄️ Database preparation**
   - Waits until MySQL accepts the connection
   - Uses `config.php` for an existing shop, and the environment variables for a new one

3. **📦 Installation detection**
   - An existing shop is one whose `config.php` already has a database hostname and username, or whose user table is already present
   - An empty volume with the install variables set is a new command-line install
   - An empty volume without those variables keeps the web installer

4. **⚡ Automatic setup**
   - A new command-line install creates the schema, the admin user, and the config files, then applies any store name or admin name you set
   - An existing shop has the 3.0.5.1 core files copied over it, and the schema is upgraded once
   - `install/` is removed after a successful install or upgrade

5. **🚀 Service startup**
   - Launches Apache
   - Makes the store available for use

The command-line installer is only used for a new shop.

## 🛡️ Security Features

- **Password validation**: a new command-line install refuses a short or weak admin or database password
- **Automatic cleanup**: `install/` is removed after a successful install or upgrade
- **Config files stay private**: Apache denies direct requests for `config.php`, `admin/config.php`, and `system/storage`
- **Environment isolation**: secrets for a new shop are managed through environment variables
- **Volume persistence**: the shop and the database live in Docker volumes, not in the container filesystem
- **Database port**: the sample compose file publishes MySQL on `127.0.0.1` only

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   OpenCart      │    │     MySQL       │
│   Container     │◄──►│   Container     │
│                 │    │                 │
│ • PHP 8.4       │    │ • MySQL 8.0     │
│ • Apache        │    │ • or Percona 8  │
│ • OpenCart      │    │ • Persistent    │
│   3.0.5.1       │    │   storage       │
└─────────────────┘    └─────────────────┘
         │
         └── volume mounted at /var/www
```

The shop files live at `/var/www/html` inside that volume. A storage directory at `/var/www/storage` is left in place.

## 📚 Advanced Usage

### Production Deployment

For a new shop behind TLS:

```bash
# Public address written during a command-line install
OPENCART_SITE_URL=https://yourdomain.com

# Strong, unique passwords
DB_PASSWORD=choose-a-long-database-password
OPENCART_PASSWORD=choose-a-long-admin-password

# Shop name and admin details. Each of these is optional.
OPENCART_SITE_NAME="Your Shop"
OPENCART_FIRSTNAME="John"
OPENCART_LASTNAME="Smith"
OPENCART_EMAIL="admin@yourdomain.com"

# Host port, if 80 is already taken
HTTP_PORT=8080
```

Terminate TLS on Traefik or another reverse proxy, and route to port 80.

For a large catalogue, or while the schema upgrade runs:

```bash
PHP_MEMORY_LIMIT=2G
PHP_MAX_EXECUTION_TIME=300
```

### Multi-Store Setup

For multiple new shops, give each one its own table prefix, name, and URL:

```bash
# Store 1
DB_PREFIX=store1_
OPENCART_SITE_NAME="Main Store"
OPENCART_SITE_URL=https://store1.yourdomain.com

# Store 2
DB_PREFIX=store2_
OPENCART_SITE_NAME="Secondary Store"
OPENCART_SITE_URL=https://store2.yourdomain.com
```

Two app containers can also share one MySQL server. Give each container its own `/var/www` volume and its own database name. The schema upgrade for a database runs once, even if a second container starts against that same database.

### Languages

OpenCart 3.0.5.1 installs in English. Add further languages afterwards from the admin, under System, then Localisation, then Languages.

### Development Setup

For local development:

```bash
# Local URL and a free host port
OPENCART_SITE_URL=http://localhost:8080
HTTP_PORT=8080

# Development-friendly settings
OPENCART_SITE_NAME="Dev Store"
OPENCART_USERNAME=dev-admin
OPENCART_FIRSTNAME=Developer
OPENCART_LASTNAME=Admin

# Higher PHP limits
PHP_MAX_EXECUTION_TIME=600
PHP_MEMORY_LIMIT=512M
```

### Database Configuration

```bash
# PDO instead of MySQLi
DB_DRIVER=pdo

# A database that is not the bundled mysql service
DB_HOSTNAME=external-db.example.com
DB_PORT=3307
DB_PREFIX=custom_

# Percona 8, for a data directory created by Percona
MYSQL_IMAGE=percona:8
```

MariaDB works with the `mysqli` driver when `DB_HOSTNAME` points at it. A new sandbox can stay on `mysql:8.0`.

### Custom Docker Images

```bash
# Pin the image for this branch
OPENCART_IMAGE=ghcr.io/aam-git/docker-opencart:3.0.5.1

# Or use your own build
OPENCART_IMAGE=your-registry/opencart:custom
```

Do not point this branch at the `latest` tag. That tag is a different OpenCart release.

## What an upgrade keeps

- `config.php` and the admin `config.php`, including a renamed admin directory, the database host, table prefix, storage path, and the public site URL
- Uploaded images under `image/`
- Storage uploads, downloads, sessions, and logs
- Extra extension files and vQmod

Core files that ship in OpenCart 3.0.5.1 are replaced with that release. A file that only exists because an extension added it is kept. The libraries in the storage `vendor/` directory are updated with this release. `cache/` and `modification/` are emptied after a successful upgrade.

## Version compatibility

| Shop you have now | What this image does |
|-------------------|----------------------|
| New, empty volume | Installs OpenCart 3.0.5.1, from the command line or the web installer |
| 3.0.3.6 or 3.0.3.8 | Upgrades the files and the database when you change the image tag |
| 3.0.4.1 | Upgrades the files and the database when you change the image tag |

OpenCart 4 is a different image. This branch does not install it.

## 🔧 Troubleshooting

### Common Issues

**Container won't start with a password error**

- This check only applies to a new command-line install
- `DB_PASSWORD` and `OPENCART_PASSWORD` must be at least 8 characters
- They must not be `password`, `123456`, `admin`, `root`, or `test`
- Change the sample placeholders before you rely on the shop

**Database connection keeps waiting**

- The first start of MySQL 8 can take a minute
- Check that `DB_PASSWORD` matches between the app and the database service
- Check that `DB_HOSTNAME` is the compose service name. On the sample file that name is `mysql`
- Check `DB_PORT` if the database is not on 3306

**The upgrade stopped and the shop did not come up**

- Read `docker compose logs opencart`. The log names the upgrade model, the file, the line, and the stack trace
- `config.php` and the admin `config.php` are restored if a model rewrote them
- A SQL dump is in the storage `backup/` directory when the dump itself succeeded
- Fix the cause and start the container again. It retries the schema upgrade

**Extensions look missing after the upgrade**

- The extension files are still on disk
- `modification/` is cleared during the upgrade
- In the admin, open Extensions, then Modifications, and refresh

**Table prefix conflicts**

- Use a unique `DB_PREFIX` for each new shop on the same database
- Use letters, numbers, and underscores only

**Port already in use**

- Change `HTTP_PORT` or `MYSQL_PORT` in `.env`
- The container still listens on port 80. Only the host port changes

**PHP execution or memory errors**

- Raise `PHP_MEMORY_LIMIT`, for example to `2G`, on shops with many extensions
- Raise `PHP_MAX_EXECUTION_TIME` if a page or the schema upgrade runs out of time
- Both are applied on every start

**Web installer appears on a shop you expected to be installed**

- The volume does not yet contain a filled `config.php`, and the command-line variables are not all set
- Fill in the admin email, password, and database variables and start again, or complete the installer in the browser

### Logs and Debugging

```bash
# View container logs
docker compose logs opencart
docker compose logs mysql

# View real-time logs
docker compose logs -f opencart

# Access the container shell
docker compose exec opencart bash
docker compose exec mysql mysql -uroot -p

# Check whether the installer is still present, and read the shop config
docker compose exec opencart ls -la /var/www/html/install
docker compose exec opencart head -n 40 /var/www/html/config.php
```

On an upgraded shop, `install/` should be absent.

## 🤝 Contributing

Contributions are welcome. Please open a pull request.

## 🔗 Links

- [OpenCart](https://www.opencart.com/)
- [GitHub repository](https://github.com/aam-git/docker-opencart)
- [Image on GitHub Container Registry](https://github.com/aam-git/docker-opencart/pkgs/container/docker-opencart)
- [Docker Hub](https://hub.docker.com/r/aamservices/opencart)
