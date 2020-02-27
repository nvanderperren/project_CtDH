#!/bin/bash
# ===============================================================================================================================
# Script to automate web-archiving with Wget
#
#	Version: 1.0 (27/02/2020)
#	Author: Maarten Savels
#       Licence: CC BY-SA 4.0 (zie: https://creativecommons.org/licenses/by-sa/4.0)
#       Dependencies: Wget must be installed
# ================================================================================================================================

set -E
trap '[ "$?" -ne 42 ] || exit 42' ERR
export LC_NUMERIC="en_US.UTF-8"  # Necessary to make correct floating point operations

IFS="$(printf '\n\t')"
ARG1="$1"  # Required
ARG2="$2"  # Optional

exit_func () {
	# Arguments passed: error message to be displayed
	# Display the error message passed and exits the subshell with exit status
	# 42; which is trapped by the error trap and exits the script
	local message="$1"
	
	printf "+++ ERROR! %s +++\n" "$message" \
		&& exit 42  # Possible exit
}

usage() {
	# Displays help message
    cat <<EOF
usage: "$0" options
    
Script accepts a list of URLs and an optional top-level directory.
The path for the top-level directory should be a full path without trailing /.
Harvests a list of websites
    
OPTIONS:
        -h --help	Show this help

SYNTAX:
    	\$ bash "$0" [OPTION] || [LIST of WEBSITES] [DIRECTORY]
              
EXAMPLE:
	Harvest websites from a list to a user-defined directory:
	       \$ bash "$0" /path/to/list/list.txt /home/harvesting_directory

EOF
}

argument_handler () {
	# Check if ARG1 and optional ARG2 are valid
	if [ -s "$ARG1" ]; then
		if [ -n "$ARG2" ]; then
			if [ -d "$ARG2" ]; then
				harvester "$ARG2"
			else
				mkdir "$ARG2" \
					|| exit_func "Unable to make top-level directory"
			fi
		elif [ -d "$HOME" ]; then
			harvester "$HOME"
		else
			exit_func "No top-level directory was found"
		fi
	else
		exit_func "List of websites is incorrect"
	fi
}

harvester () {
	# Makes the necessary folder structure and harvests websites
	local top_dir="$1"
	local harvest_dir
	local master_log
	local line
	local website
	local web_dir
	local data_dir
	local metadata_dir
	local metadata_file
	local logfile
	local output_file
	local warc_file
	local start_time
	local start
	local end
	local runtime
	local software
	local options
	local warc_gz_file
	local warc_size
	local html_size
	
	harvest_dir="$top_dir""/harvesting_""$(date +%Y%m%d)"
	if [ ! -d "$harvest_dir" ]; then
		mkdir "$harvest_dir" || exit_func "Unable to create harvesting directory"
	fi
	master_log="$harvest_dir""/harvesting_""$(date +%Y%m%d)"".csv"
	printf "URL\tsoftware\toptions\tstarting time\truntime (seconds)\tWARC-size (GB)\tHTML-size (GB)\n">> "$master_log"
		
	while read -r line; do
		cd "$top_dir" || exit_func "Top-level directory not cd'able"
		website="${line%;*}"
		web_dir="$harvest_dir""/""${line#*;}"
		data_dir="$harvest_dir""/""${line#*;}""/data"
		metadata_dir="$harvest_dir""/""${line#*;}""/metadata"
		mkdir "$web_dir" || exit_func "Unable to create website directory"
		mkdir "$data_dir" || exit_func "Unable to create data directory"
		mkdir "$metadata_dir" || exit_func "Unable to create metadata directory"
		metadata_file="$metadata_dir""/_metadata_dragers.txt"
		logfile="$metadata_dir""/wget_logfile.txt"
		output_file="$metadata_dir""/wget_outputfile.txt"
		touch "$metadata_file"
		touch "$logfile"
		touch "$output_file"
		cat > "$metadata_file" << EOF
Persistent Identifier (PID):
Archiefvormer:

Dragers (0):
Snapshot van de website $website van $(date +%d/%m/%Y)

Opmerkingen:

Fouten:

Selectie:
EOF
		
		cd "$data_dir" || exit_func "$data_dir"" not cd'able"
		start_time="$(date +%F" "%T)"
		start=$SECONDS
		wget -e "robots=off" \
		     -m \
		     -nv \
		     --output-file="../metadata/wget_outputfile.txt" \
		     --warc-file="${line#*;}" \
		     --page-requisites \
		     --html-extension \
		     --convert-links \
		     -w "0.1" \
		     "$website"
		     
		end=$SECONDS
		runtime=$((end - start))
		software="$(wget -V | head -1)"
		software="${software%??}"  # removes last 2 chars. Necessary for removing \r\n in Windows only!
		options="--execute=robots=off, --mirror, --no-verbose, --warc-file, --page-requisites, --html-extension, --convert-links, -w 0.1"
		warc_file="${line#*;}"".warc"
		if [ -f "$warc_file" ]; then
			warc_size="$(du -s -B 1 "$warc_file" | cut -f1)"  # filesize in B
 			warc_size=$(bc <<< "scale=4;$warc_size / (1024^3)")  # filesize in GiB
		elif [ -f "$warc_file"".gz" ]; then
			warc_gz_file="$warc_file"".gz"
			warc_size="$(du -s -B 1 "$warc_gz_file" | cut -f1)"  # filesize in B
 			warc_size=$(bc <<< "scale=4;$warc_size / (1024^3)")  # filesize in GiB
		else
			warc_size="+++ WARC NOT FOUND +++"
		fi
		if [ -d "$website" ]; then
			html_size="$(du -s -B 1 "$website" | cut -f1)"  # folder size in B
			html_size=$(bc <<< "scale=4;$html_size / (1024^3)")  # folder size in GiB
		else
			html_size="+++ HTML NOT FOUND +++"
		fi
		{
		printf "Software: %s\n" "$software"
		printf "Options: %s\n" "$options"
		printf "URL: %s\n" "$website"
		printf "Start time: %s\n" "$start_time"
		printf "Running time: %s seconds\n" "$runtime"
		printf "Size of WARC-file: %0.4f GiB\n" "$warc_size"
		printf "Size of HTML-files: %0.4f GiB\n" "$html_size"
		}>> "$logfile"
		printf "%s\t%s\t%s\t%s\t%s\t%0.4f\t%0.4f\n" \
	               "$website" \
	               "$software" \
	               "$options" \
	               "$start_time" \
	               "$runtime" \
	               "$warc_size" \
	               "$html_size">> "$master_log"
	done <"$ARG1"
}

main() {
	# Starting point of the script
	case "$ARG1" in
		-h|--help ) usage;;
		* ) argument_handler;;
	esac
}

main
