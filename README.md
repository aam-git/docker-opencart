# OpenCart 4.1.0.3 Docker Container

[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![OpenCart](https://img.shields.io/badge/OpenCart-4.1.0.3-blue?style=for-the-badge)](https://www.opencart.com/)
[![PHP](https://img.shields.io/badge/PHP-8.3--apache-777BB4?style=for-the-badge&logo=php&logoColor=white)](https://php.net/)
[![MySQL](https://img.shields.io/badge/MySQL-8.4-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://mysql.com/)

A production-ready, fully automated Docker setup for [OpenCart](https://www.opencart.com/) e-commerce platform with zero-configuration deployment.

## ✨ Features

- **🚀 Fully Automated Installation** - Zero manual configuration required
- **🔒 Security-First Design** - Enforced password validation and secure defaults  
- **🐳 Multi-Container Architecture** - Separate database and application containers
- **⚙️ Environment-Based Configuration** - Flexible `.env` file management
- **🛡️ Production Ready** - Optimized for both development and production environments
- **🔄 Persistent Data** - Docker volumes ensure data persistence across container restarts

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
| `MYSQL_VERSION` | MySQL Docker image version | `8.4` |
| `OPENCART_IMAGE` | OpenCart Docker image | `aamservices/opencart:4.1.0.3` |
| `HTTP_PORT` | HTTP port mapping | `80` |
| `HTTPS_PORT` | HTTPS port mapping | `443` |

#### 🗄️ Database Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOSTNAME` | Database hostname | `database` |
| `DB_PORT` | Database port | `3306` |
| `DB_DATABASE` | Database name | `opencart` |
| `DB_USERNAME` | Database username | `root` |

#### 🏪 Store Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCART_USERNAME` | Admin username | `admin` |
| `OPENCART_SITE_NAME` | Store name | `My OpenCart Store` |
| `OPENCART_SITE_URL` | Store URL | `http://localhost` |

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
│ • PHP 8.3       │    │ • MySQL 8.4     │
│ • Apache 2      │    │ • Persistent    │
│ • OpenCart 4.1  │    │   Storage        │
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

# Configure proper ports (if needed)
HTTP_PORT=8080
HTTPS_PORT=8443
```

### Development Setup

For local development:

```bash
# Use local URLs
OPENCART_SITE_URL=http://localhost:3000

# Use development-friendly settings
OPENCART_SITE_NAME=Dev Store
OPENCART_USERNAME=dev-admin
```

### Custom Docker Images

Override the default images:

```bash
# Use custom MySQL version
MYSQL_VERSION=8.0

# Use custom OpenCart build
OPENCART_IMAGE=your-registry/opencart:custom
```

## 🔧 Troubleshooting

### Common Issues

**Container won't start with password error**
- Ensure `DB_PASSWORD` and `OPENCART_PASSWORD` are changed from defaults
- Verify passwords are at least 8 characters long

**Database connection failed**
- Wait for MySQL container to fully initialize (can take 30-60 seconds)
- Check that `DB_PASSWORD` matches between containers

**Port already in use**
- Modify `HTTP_PORT` and `HTTPS_PORT` in your `.env` file
- Ensure no other services are using ports 80/443

### Logs and Debugging

```bash
# View container logs
docker-compose logs opencart
docker-compose logs database

# Access container shell
docker-compose exec opencart bash
docker-compose exec database mysql -uroot -p
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
