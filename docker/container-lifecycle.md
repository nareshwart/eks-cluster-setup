# 🐳 Docker Container Lifecycle Commands

---

## 1. Image Management (Before Container)

| Command | Description |
|---|---|
| `docker pull <image>` | Download an image from Docker Hub |
| `docker images` | List all local images |
| `docker image ls` | Same as above |
| `docker rmi <image>` | Remove an image |
| `docker image inspect <image>` | Show detailed info about an image |
| `docker image prune` | Remove all unused/dangling images |
| `docker build -t <name>:<tag> .` | Build an image from a Dockerfile |

### Examples
```bash
docker pull nginx
docker pull ubuntu:22.04
docker build -t myapp:v1 .
docker images
docker rmi nginx
```

---

## 2. Creating Containers

| Command | Description |
|---|---|
| `docker create <image>` | Create a container without starting it |
| `docker run <image>` | Create and start a container |
| `docker run -d <image>` | Run container in detached (background) mode |
| `docker run -it <image> bash` | Run container interactively with a shell |
| `docker run --name <name> <image>` | Assign a custom name to the container |
| `docker run -p <host>:<container> <image>` | Map host port to container port |
| `docker run --rm <image>` | Auto-remove container when it exits |
| `docker run -e VAR=value <image>` | Pass environment variables |
| `docker run -v <host_path>:<container_path> <image>` | Mount a volume |

### Examples
```bash
# Run nginx in the background on port 8080
docker run -d --name webserver -p 8080:80 nginx

# Run ubuntu interactively
docker run -it --name myubuntu ubuntu bash

# Run with environment variables
docker run -d --name mydb -e MYSQL_ROOT_PASSWORD=secret mysql

# Run and auto-remove on exit
docker run --rm ubuntu echo "Hello World"
```

---

## 3. Starting & Stopping Containers

| Command | Description |
|---|---|
| `docker start <container>` | Start a stopped container |
| `docker stop <container>` | Gracefully stop a running container (SIGTERM) |
| `docker restart <container>` | Stop and then start a container |
| `docker kill <container>` | Force stop a container immediately (SIGKILL) |
| `docker pause <container>` | Pause all processes in a container |
| `docker unpause <container>` | Resume a paused container |

### Examples
```bash
docker start webserver
docker stop webserver
docker restart webserver
docker kill webserver
docker pause webserver
docker unpause webserver
```

---

## 4. Monitoring & Inspecting Containers

| Command | Description |
|---|---|
| `docker ps` | List all running containers |
| `docker ps -a` | List all containers (including stopped) |
| `docker ps -q` | List only container IDs |
| `docker logs <container>` | View logs of a container |
| `docker logs -f <container>` | Follow (tail) logs in real time |
| `docker logs --tail 50 <container>` | View last 50 lines of logs |
| `docker inspect <container>` | Show detailed low-level info (JSON) |
| `docker stats` | Live CPU/memory/network usage of all containers |
| `docker stats <container>` | Live stats for a specific container |
| `docker top <container>` | Show running processes inside a container |
| `docker port <container>` | Show port mappings of a container |
| `docker diff <container>` | Show filesystem changes made in the container |

### Examples
```bash
docker ps -a
docker logs -f webserver
docker inspect webserver
docker stats webserver
docker top webserver
```

---

## 5. Executing Commands Inside a Running Container

| Command | Description |
|---|---|
| `docker exec <container> <command>` | Run a command in a running container |
| `docker exec -it <container> bash` | Open an interactive shell inside the container |
| `docker exec -it <container> sh` | Use sh if bash is not available |
| `docker attach <container>` | Attach your terminal to a running container |

### Examples
```bash
# Open a shell inside a running container
docker exec -it webserver bash

# Run a single command inside a container
docker exec webserver ls /etc/nginx

# Check environment variables inside a container
docker exec mydb env
```

---

## 6. Copying Files

| Command | Description |
|---|---|
| `docker cp <container>:<src_path> <dest_path>` | Copy files FROM container to host |
| `docker cp <src_path> <container>:<dest_path>` | Copy files FROM host to container |

### Examples
```bash
# Copy a log file from container to your local machine
docker cp webserver:/var/log/nginx/access.log ./access.log

# Copy a config file from your machine into a container
docker cp ./nginx.conf webserver:/etc/nginx/nginx.conf
```

---

## 7. Removing Containers

| Command | Description |
|---|---|
| `docker rm <container>` | Remove a stopped container |
| `docker rm -f <container>` | Force remove a running container |
| `docker rm $(docker ps -aq)` | Remove ALL stopped containers |
| `docker container prune` | Remove all stopped containers (with confirmation) |

### Examples
```bash
docker rm webserver
docker rm -f webserver
docker container prune
```

---

## 8. Saving & Exporting

| Command | Description |
|---|---|
| `docker commit <container> <new_image>` | Create a new image from a container's current state |
| `docker export <container> > file.tar` | Export container filesystem as a tar archive |
| `docker import file.tar <image_name>` | Import a tar archive as a new image |
| `docker save -o file.tar <image>` | Save an image to a tar file |
| `docker load -i file.tar` | Load an image from a tar file |

### Examples
```bash
# Save running container state as a new image
docker commit webserver my-nginx:custom

# Export container to a tar file
docker export webserver > webserver.tar

# Save an image to a file and transfer it
docker save -o nginx.tar nginx
docker load -i nginx.tar
```

---

## 9. Networking

| Command | Description |
|---|---|
| `docker network ls` | List all networks |
| `docker network create <name>` | Create a custom network |
| `docker network inspect <name>` | Inspect a network |
| `docker network connect <network> <container>` | Connect a container to a network |
| `docker network disconnect <network> <container>` | Disconnect a container from a network |
| `docker network rm <name>` | Remove a network |

### Examples
```bash
# Create a custom bridge network
docker network create mynetwork

# Run containers on the same network so they can communicate by name
docker run -d --name db --network mynetwork mysql
docker run -d --name app --network mynetwork myapp

# Containers can now reach each other using their names e.g. 'db' and 'app'
```

---

## 10. Volume Management

| Command | Description |
|---|---|
| `docker volume ls` | List all volumes |
| `docker volume create <name>` | Create a named volume |
| `docker volume inspect <name>` | Inspect a volume |
| `docker volume rm <name>` | Remove a volume |
| `docker volume prune` | Remove all unused volumes |

### Examples
```bash
# Create and use a named volume
docker volume create mydata
docker run -d --name db -v mydata:/var/lib/mysql mysql

# Mount a host directory (bind mount)
docker run -d --name app -v /home/ec2-user/app:/app myapp
```

---

## 11. System Cleanup (Important!)

| Command | Description |
|---|---|
| `docker system df` | Show docker disk usage |
| `docker system prune` | Remove all stopped containers, unused networks, dangling images |
| `docker system prune -a` | Remove everything including unused images |
| `docker system prune -a --volumes` | Remove everything including volumes |

> ⚠️ **Warning**: `docker system prune -a --volumes` is destructive. It will remove all data stored in volumes. Use with caution!

---

## 12. Full Container Lifecycle Summary

```
     ┌─────────────┐
     │   docker    │
     │    pull     │
     └──────┬──────┘
            │ Image Downloaded
            ▼
     ┌─────────────┐       docker create
     │   Created   │ ◄─────────────────────
     └──────┬──────┘
            │ docker start / docker run
            ▼
     ┌─────────────┐
     │   Running   │ ◄──── docker restart
     └──────┬──────┘
            │
     ┌──────┴──────┐
     │   docker    │ docker stop / docker kill
     │   Stopped   │ ──────────────────────►
     └──────┬──────┘
            │ docker rm
            ▼
     ┌─────────────┐
     │   Removed   │
     └─────────────┘
```

---

## 13. Quick Reference Cheat Sheet

```bash
# === IMAGE ===
docker pull nginx                          # Pull image
docker images                              # List images
docker rmi nginx                           # Remove image
docker build -t myapp:v1 .                 # Build image

# === CREATE & RUN ===
docker run -d --name web -p 80:80 nginx    # Run detached
docker run -it ubuntu bash                 # Run interactive

# === STATUS ===
docker ps                                  # Running containers
docker ps -a                               # All containers
docker logs -f web                         # Follow logs
docker stats                               # Live stats

# === CONTROL ===
docker start web                           # Start container
docker stop web                            # Stop container
docker restart web                         # Restart container
docker kill web                            # Force kill

# === SHELL ACCESS ===
docker exec -it web bash                   # Enter shell

# === CLEANUP ===
docker stop web && docker rm web           # Stop and remove
docker container prune                     # Remove all stopped
docker system prune -a                     # Full cleanup
```
