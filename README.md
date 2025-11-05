# OpenCart Docker Container

[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![OpenCart](https://img.shields.io/badge/OpenCart-v3%20%7C%20v4-blue?style=for-the-badge)](https://www.opencart.com/)
[![PHP](https://img.shields.io/badge/PHP-8.4--apache-777BB4?style=for-the-badge&logo=php&logoColor=white)](https://php.net/)
[![MySQL](https://img.shields.io/badge/MySQL-9.5-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://mysql.com/)

A production-ready, fully automated Docker setup for [OpenCart](https://www.opencart.com/) e-commerce platform with zero-configuration deployment. Supports both OpenCart v3.x and v4.x with automatic version detection.

## ✨ Features

- **🚀 Fully Automated Installation** - Zero manual configuration required
- **🔒 Security-First Design** - Enforced password validation and secure defaults  
- **🐳 Multi-Container Architecture** - Separate database and application containers
- **⚙️ Comprehensive Configuration** - 15+ environment variables for complete customization
- **🌍 Multi-Language Support** - OpenCart v4+ language selection during installation
- **🏪 Multi-Store Ready** - Configurable table prefixes for multiple stores
- **🔄 Version Agnostic** - Supports both OpenCart v3.x and v4.x automatically
- **🛡️ Production Ready** - Optimized for both development and production environments
- **� Persistent Data** - Docker volumes ensure data persistence across container restarts
- **🔧 Flexible Database Options** - Support for MySQL, MariaDB with multiple drivers

## 🚀 Quick Start

Get your OpenCart store running in under 2 minutes:

```bash
# Download configuration files
curl -sSL https://raw.githubusercontent.com/aam-git/docker-opencart/latest/docker-compose.yml > docker-compose.yml
curl -sSL https://raw.githubusercontent.com/aam-git/docker-opencart/latest/.env.example > .env

# Configure your environment (edit passwords, email, etc.)
nano .env

# Deploy your store
docker-compose up -d

# Access your store
open http://localhost
```

## ⚙️ Configuration

### Environment Variables

All configuration is managed through environment variables in your `.env` file. The system uses secure defaults but requires customization of security-sensitive values.

#### 🔐 Required Security Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DB_PASSWORD` | Database root password | `please_change_this_password` | ✅ |
| `OPENCART_PASSWORD` | Admin account password | `please_change_this_password` | ✅ |
| `OPENCART_EMAIL` | Admin email address | `admin@example.com` | ✅ |

#### 🐳 Container Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `MYSQL_VERSION` | MySQL Docker image version | `9.5` |
| `OPENCART_IMAGE` | OpenCart Docker image | `ghcr.io/aam-git/docker-opencart:latest` |
| `HTTP_PORT` | HTTP port mapping | `80` |
| `HTTPS_PORT` | HTTPS port mapping | `443` |
| `MYSQL_PORT` | MySQL port mapping | `3306` |

#### 🗄️ Database Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOSTNAME` | Database hostname | `database` |
| `DB_PORT` | Database port | `3306` |
| `DB_DATABASE` | Database name | `opencart` |
| `DB_USERNAME` | Database username | `root` |
| `DB_DRIVER` | Database driver (mysqli/pdo/pgsql) | `mysqli` |
| `DB_PREFIX` | Database table prefix | `oc_` |

#### 🏪 Store Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCART_USERNAME` | Admin username | `admin` |
| `OPENCART_FIRSTNAME` | Admin first name | `Admin` |
| `OPENCART_LASTNAME` | Admin last name | `User` |
| `OPENCART_SITE_NAME` | Store name | `My OpenCart Store` |
| `OPENCART_SITE_URL` | Store URL | `http://localhost` |
| `OPENCART_LANGUAGE` | Installation language (v4+ only) | `en-gb` |

#### ⚡ PHP Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `PHP_MAX_EXECUTION_TIME` | Script execution timeout (seconds) | `300` |
| `PHP_MEMORY_LIMIT` | PHP memory limit | `256M` |

> **📋 Complete Reference**: See `.env.example` for detailed explanations and additional options.

## 🔄 Automated Installation Process

The container performs intelligent automation on startup:

1. **🔍 Environment Validation**
   - Validates all required environment variables
   - Enforces secure password requirements (minimum 8 characters)
   - Blocks startup with insecure default passwords

2. **🗄️ Database Preparation**
   - Waits for MySQL container to become available
   - Establishes database connectivity

3. **📦 Installation Detection**
   - Checks for existing OpenCart installation
   - Determines if setup is required

4. **⚡ Automatic Setup** (if needed)
   - Configures database connections
   - Executes database schema installation
   - Creates administrative user account
   - Applies initial site configuration
   - Removes installation files for security

5. **🚀 Service Startup**
   - Launches Apache web server
   - Makes store available for use

## 🛡️ Security Features

- **Password Validation**: Container refuses to start with default or weak passwords
- **Automatic Cleanup**: Installation directories removed post-setup
- **Secure Defaults**: All configuration uses security-first principles
- **Environment Isolation**: Secrets managed through environment variables
- **Volume Persistence**: Data stored in Docker volumes, not containers

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   OpenCart      │    │     MySQL       │
│   Container     │◄──►│   Container     │
│                 │    │                 │
│ • PHP 8.4       │    │ • MySQL 9.5     │
│ • Apache 2      │    │ • Persistent    │
│ • OpenCart 3.0  │    │   Storage       │
└─────────────────┘    └─────────────────┘
```

## 📚 Advanced Usage

### Production Deployment

For production environments, ensure you:

```bash
# Use HTTPS and proper domain
OPENCART_SITE_URL=https://yourdomain.com

# Use strong, unique passwords
DB_PASSWORD=$(openssl rand -base64 32)
OPENCART_PASSWORD=$(openssl rand -base64 24)

# Configure proper admin details
OPENCART_FIRSTNAME="John"
OPENCART_LASTNAME="Smith"
OPENCART_EMAIL="admin@yourdomain.com"

# Configure proper ports (if needed)
HTTP_PORT=8080
HTTPS_PORT=8443
```

### Multi-Store Setup

For multiple OpenCart instances:

```bash
# Store 1 Configuration
DB_PREFIX=store1_
OPENCART_SITE_NAME="Main Store"
OPENCART_SITE_URL=https://store1.yourdomain.com

# Store 2 Configuration  
DB_PREFIX=store2_
OPENCART_SITE_NAME="Secondary Store"
OPENCART_SITE_URL=https://store2.yourdomain.com
```

### Multi-Language Installation

For non-English installations (OpenCart v4+ only):

```bash
# French installation
OPENCART_LANGUAGE=fr-fr
OPENCART_SITE_NAME="Ma Boutique"

# German installation
OPENCART_LANGUAGE=de-de
OPENCART_SITE_NAME="Mein Shop"

# Spanish installation
OPENCART_LANGUAGE=es-es
OPENCART_SITE_NAME="Mi Tienda"
```

### Development Setup

For local development:

```bash
# Use local URLs
OPENCART_SITE_URL=http://localhost:3000

# Use development-friendly settings
OPENCART_SITE_NAME=Dev Store
OPENCART_USERNAME=dev-admin
OPENCART_FIRSTNAME=Developer
OPENCART_LASTNAME=Admin

# Increase PHP limits for development
PHP_MAX_EXECUTION_TIME=600
PHP_MEMORY_LIMIT=512M
```

### Database Configuration

Advanced database setups:

```bash
# Use PDO driver instead of MySQLi
DB_DRIVER=pdo

# Custom database configuration
DB_HOSTNAME=external-db.example.com
DB_PORT=3307
DB_PREFIX=custom_

# For high-traffic sites
MYSQL_VERSION=8.0
```

### Custom Docker Images

Override the default images:

```bash
# Use custom MySQL version
MYSQL_VERSION=8.0

# Use custom OpenCart build
OPENCART_IMAGE=your-registry/opencart:custom

# Use specific testing builds
OPENCART_IMAGE=ghcr.io/aam-git/docker-opencart:latest
```

## � Version Compatibility

This Docker container automatically detects and supports:

| OpenCart Version | SQL File | Language Support | Auto-Detection |
|------------------|----------|------------------|----------------|
| **v4.1.0.3** | `opencart-en-gb.sql` | ✅ Multi-language | ✅ Automatic |
| **v3.0.4.1** | `opencart.sql` | ⚠️ Post-install only | ✅ Automatic |

The container automatically adapts its installation parameters based on the detected OpenCart version, ensuring seamless compatibility.

## �🔧 Troubleshooting

### Common Issues

**Container won't start with password error**
- Ensure `DB_PASSWORD` and `OPENCART_PASSWORD` are changed from defaults
- Verify passwords are at least 8 characters long
- Check that passwords don't contain reserved/weak values

**Database connection failed**
- Wait for MySQL container to fully initialize (can take 30-60 seconds)
- Check that `DB_PASSWORD` matches between containers
- Verify `DB_HOSTNAME` and `DB_PORT` are correct

**Language not found error (v4+ only)**
- Ensure the language SQL file exists: `install/opencart-{OPENCART_LANGUAGE}.sql`
- Check available languages in the install directory
- Default to `en-gb` if your preferred language is unavailable

**Table prefix conflicts**
- Use unique `DB_PREFIX` values for multiple installations
- Ensure prefix doesn't conflict with existing tables
- Use alphanumeric characters and underscores only

**Port already in use**
- Modify `HTTP_PORT`, `HTTPS_PORT`, and `MYSQL_PORT` in your `.env` file
- Ensure no other services are using the configured ports

**PHP execution or memory errors**
- Increase `PHP_MAX_EXECUTION_TIME` for complex installations
- Raise `PHP_MEMORY_LIMIT` for sites with many extensions
- Values are applied during installation process

### Logs and Debugging

```bash
# View container logs
docker-compose logs opencart
docker-compose logs database

# View real-time logs
docker-compose logs -f opencart

# Access container shell
docker-compose exec opencart bash
docker-compose exec database mysql -uroot -p

# Check OpenCart installation status
docker-compose exec opencart ls -la /var/www/html/install/
docker-compose exec opencart cat /var/www/html/config.php
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🔗 Links

- [OpenCart Official Website](https://www.opencart.com/)
- [Docker Hub Repository](https://hub.docker.com/r/aamservices/opencart)
- [GitHub Repository](https://github.com/aam-git/docker-opencart)


[1]: http://www.opencart.com/index.php
