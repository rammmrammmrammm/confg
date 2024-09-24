   #!/bin/bash
   # Path to the PostgreSQL configuration file
   PG_CONF="/etc/postgresql/16/main/postgresql.conf"

   # Function to update or add a configuration setting
   update_config() {
       local key=$1
       local value=$2
       if grep -q "^#*$key" $PG_CONF; then
           sed -i "s|^#*$key.*|$key = $value|" $PG_CONF
       else
           echo "$key = $value" >> $PG_CONF
       fi
   }

   # Monitor PostgreSQL performance and adjust settings
   adjust_settings() {
       # Get the current number of active connections
       current_connections=$(psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;" -t | xargs)

       # Adjust max_connections based on current load (requires restart)
       if [ "$current_connections" -lt 1000 ]; then
           update_config "max_connections" "1000"
       elif [ "$current_connections" -lt 10000 ]; then
           update_config "max_connections" "10000"
       elif [ "$current_connections" -lt 100000 ]; then
           update_config "max_connections" "100000"
       elif [ "$current_connections" -lt 1000000]; then
           update_config "max_connections" "1000000"
       else
           update_config "max_connections" "10000000"
       fi

       # Get the available memory in MB
       available_memory=$(free -m | awk '/^Mem:/{print $7}')

       # Adjust work_mem based on available memory (reloadable)
       if [ "$available_memory" -lt 1024 ]; then
           update_config "work_mem" "32MB"
       elif [ "$available_memory" -lt 4096 ]; then
           update_config "work_mem" "64MB"
       elif [ "$available_memory" -lt 16384 ]; then
           update_config "work_mem" "128MB"
       else
           update_config "work_mem" "256MB"
       fi

       # Get the current CPU usage
       cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

       # Adjust maintenance_work_mem based on CPU usage (reloadable)
       if (( $(echo "$cpu_usage < 20.0" | bc -l) )); then
           update_config "maintenance_work_mem" "512MB"
       elif (( $(echo "$cpu_usage < 50.0" | bc -l) )); then
           update_config "maintenance_work_mem" "256MB"
       else
           update_config "maintenance_work_mem" "128MB"
       fi

       # Get the current disk I/O wait time
       io_wait=$(iostat -c | awk 'NR==4 {print $4}')

       # Adjust checkpoint_completion_target based on I/O wait time (reloadable)
       if (( $(echo "$io_wait < 5.0" | bc -l) )); then
           update_config "checkpoint_completion_target" "0.9"
       elif (( $(echo "$io_wait < 10.0" | bc -l) )); then
           update_config "checkpoint_completion_target" "0.7"
       else
           update_config "checkpoint_completion_target" "0.5"
       fi

       # Reload PostgreSQL configuration to apply changes
       psql -U postgres -c "SELECT pg_reload_conf();"

       # Schedule a restart if necessary
       if grep -q "max_connections" $PG_CONF; then
           echo "Scheduling PostgreSQL restart to apply changes to max_connections..."
           echo "sudo systemctl restart postgresql" | at now + 5 minutes
       fi
   }

   # Run the adjustment function
   adjust_settings

   echo "PostgreSQL configuration adjusted and reloaded based on current load and performance."
   
