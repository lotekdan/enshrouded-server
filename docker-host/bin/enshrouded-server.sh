#!/bin/bash

# This script is used to manage the Enshrouded server using Docker Compose.
# It provides commands to start, stop, restart, clean-restart, backup, and view logs of the server.

VERSION="2.0.1"
# Enable extended pattern matching features for the clean and backup functions
shopt -s extglob

# Define color codes for terminal output
GREEN='\e[32m'
RED='\e[31m'
CYAN='\e[36m'
YELLOW='\e[33m'
BOLD='\e[1m'
NC='\e[0m'

# Function to resolve the directory of the current script, even if it's a symlink
function resolve_script_dir() {
    # Get the source of the script
    local SOURCE=${BASH_SOURCE[0]}

    # Resolve symlinks 
    while [ -L "$SOURCE" ]; do
        # Get the directory of the symlink
        local DIR=$( cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
        
        # Resolve the symlink to its target
        SOURCE=$(readlink "$SOURCE")
        
        # If the resolved source is not an absolute path, prepend the directory of the symlink
        [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE
    done

    # Return the directory of the resolved script
    echo $( cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
}

# Function to clean up the data directory and restart the Enshrouded server
function clean_restart() {
    printf "${BOLD}${CYAN}Cleaning up and restarting the Enshrouded server...${NC}\n"
    
    # Stop the Docker containers
    docker compose down
    
    # Remove all files in the data directory except for enshrouded_server.json and savegame
    cd ../data
    rm -rf !(enshrouded_server.json|savegame)
    
    # Start the Docker containers
    docker compose up -d
}

# Function to back up the Enshrouded server data
function backup_data() {
    printf "${BOLD}${CYAN}Backing up Enshrouded server data...${NC}\n"
    
    # Create a timestamped backup directory
    local backup_dir="../data-backup-$(date +%Y%m%d_%H%M%S)"
    
    # List existing backups sorted by modification time (newest first)
    local existing_backups=($(ls -dt ../data-backup-* 2>/dev/null))

    # If there are 3 or more existing backups, remove the oldest ones
    if [ "${#existing_backups[@]}" -ge 3 ]; then
        printf "Found ${YELLOW}${#existing_backups[@]}${NC} existing backups.\n${RED}Cleaning up oldest...${NC}\n"

        # Loop through the existing backups starting from the third one (index 2) and remove them
        for ((i=2; i<${#existing_backups[@]}; i++)); do
            printf "${YELLOW}${BOLD}Removing old backup:${NC} ${existing_backups[$i]}\n"
        
            # Remove the old backup directory
            rm -rf "${existing_backups[$i]}"
        done      
    fi

    # Create the new backup directory and copy the necessary files
    mkdir -p "$backup_dir"
    cp -r {../data/enshrouded_server.json,../data/savegame} "$backup_dir/"

    printf "${GREEN}${BOLD}Backup completed:${NC} $backup_dir\n"
}

function server_status() {
    printf "${BOLD}${CYAN}Checking Enshrouded server status...${NC}\n\n"
    
    # Check if the Docker containers are running
    local status=$(docker compose ps --services --filter "status=running")
    
    # Display the status of the Enshrouded server
    # If no services are running, indicate that the server is not running; otherwise, display the running services and their information.
    if [ -z "$status" ]; then
        printf "${BOLD}The Enshrouded server is ${RED}not running.${NC}\n\n"
    else
        printf "${BOLD}The Enshrouded server is ${GREEN}running.${NC}\n\n"
        printf "${BOLD}Running services:${NC}\n${GREEN}%s\n\n" "$status"
        local info=$(docker ps --filter "name=enshrouded-server" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.RunningFor}}")
        printf "${BOLD}Info:${NC}\n%s\n" "$info"
    fi
}

function edit_server_config() {
    printf "${BOLD}${CYAN}Opening Enshrouded server configuration for editing...${NC}\n"
    
    # Check if the configuration file exists
    local config_file="../data/enshrouded_server.json"
    if [ ! -f "$config_file" ]; then
        printf "${RED}${BOLD}Configuration file not found:${NC} $config_file\n"
        return 1
    fi

    # Open the configuration file in the default editor (nano, vim, etc.)
    ${EDITOR:-nano} "$config_file"
}

function edit_docker_compose() {
    printf "${BOLD}${CYAN}Opening Docker Compose configuration for editing...${NC}\n"
    
    # Check if the docker-compose.yml file exists
    local compose_file="../docker-compose.yml"
    if [ ! -f "$compose_file" ]; then
        printf "${RED}${BOLD}Docker Compose file not found:${NC} $compose_file\n"
        return 1
    fi

    # Open the docker-compose.yml file in the default editor (nano, vim, etc.)
    ${EDITOR:-nano} "$compose_file"
}

# Function to display usage information for the script
function show_usage() {
  local cmd_width=16
  local total_width=100
  local desc_indent
  desc_indent=$(printf '%*s' $((cmd_width + 4)) '')

  printf "${BOLD}Usage: ${CYAN}%s ${GREEN}[command]${NC}\n\n" "$(basename $0)"
  printf "${BOLD}Commands:%*sFunction:${NC}\n" $((cmd_width - 8)) ''

  print_cmd() {
    local color="$1"
    local cmd="$2"
    local desc="$3"

    printf "  %b%-${cmd_width}s%b " "$color" "$cmd" "$NC"
    echo "$desc" | fold -s -w $((total_width - cmd_width - 4)) \
      | sed "2,\$s/^/${desc_indent}/"
  }

  print_cmd "${GREEN}${BOLD}"  "start"          "Start the Enshrouded server"
  print_cmd "${RED}${BOLD}"    "stop"           "Stop the Enshrouded server"
  print_cmd "${YELLOW}${BOLD}" "restart"        "Restart the Enshrouded server"
  print_cmd "${CYAN}${BOLD}"   "clean-restart"  "Back up and clean up then restart the Enshrouded server. Intended for clearing potential cache or corrupted data issues."
  print_cmd "${GREEN}${BOLD}"  "backup"         "Backup the Enshrouded server data. Keeps the last 3 backups and removes older ones."
  print_cmd "${YELLOW}${BOLD}"   "status"         "Show the current status of the Enshrouded server, including running services and their information."
  print_cmd "${CYAN}${BOLD}"   "log"            "Show the active console log of the Enshrouded server. Use Ctrl+C to exit the log view."
  print_cmd "${GREEN}${BOLD}"   "edit-config"    "Edit the Enshrouded server configuration file."
  print_cmd "${CYAN}${BOLD}"   "edit-compose"   "Edit the Docker Compose configuration file."
}

# Function to display help information for the script
function show_help() {
    printf "%b\n" "$(cat <<-EOF
	${CYAN}${BOLD}Enshrouded Server Manager${NC}
	============================
	Version: $VERSION
	
	Designed to work with the ${YELLOW}\e]8;;https://github.com/mbround18/enshrouded-docker\e\\\\mbround18/enshrouded-docker:proton-latest\e]8;;\e\\\\${NC} docker container.
	
	This tool allows you to manage the Enshrouded server using Docker Compose. 
	============================
EOF
)"
show_usage
}    

# Function to start the Enshrouded server using Docker Compose
function start_server() {
    printf "${GREEN}${BOLD}Starting the Enshrouded server...\n${NC}"
    docker compose up -d
}

# Function to stop the Enshrouded server using Docker Compose
function stop_server() {
    printf "${RED}${BOLD}Stopping the Enshrouded server...\n${NC}"
    docker compose down
}

# Function to restart the Enshrouded server by stopping and then starting it
function restart_server() {
    printf "${YELLOW}${BOLD}Restarting the Enshrouded server...\n${NC}"
    stop_server
    start_server
}

# Function to perform a clean restart of the Enshrouded server by backing up data and cleaning up before restarting
function clean_restart_server() {
    printf "${CYAN}${BOLD}Performing a clean restart of the Enshrouded server...\n${NC}"
    backup_data
    clean_restart
}

# Function to display the logs of the Enshrouded server using Docker Compose
function log_server() {
    printf "${GREEN}${BOLD}Displaying logs for the Enshrouded server...\n${NC}"
    docker compose logs -f
}

# Main script execution starts here
# ----------------------------------
# Resolve the script directory and change to it
function main() {
    cd $(resolve_script_dir)

    # Check if any arguments are provided; if not, display usage information
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    # Process command-line arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            --version)
                printf "Enshrouded Server Manager Version: $VERSION\n"
                exit 0
                ;;
            start)
                start_server
                exit 0
                ;;
            stop)
                stop_server
                exit 0
                ;;
            restart)
                restart_server
                exit 0
                ;;
            clean-restart)
                clean_restart_server
                exit 0
                ;;
            backup)
                backup_data
                exit 0
                ;;
            status)
                server_status
                exit 0
                ;;
            log)
                log_server
                exit 0
                ;;
            edit-config)
                edit_server_config
                exit 0
                ;;
            edit-compose)
                edit_docker_compose
                exit 0
                ;;
            *)
                printf "Unknown command: $1\n"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Call the main function with all the script arguments
main "$@"