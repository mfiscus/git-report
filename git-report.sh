#!/usr/bin/env bash

# This tool was written to parse git logs to generate a report for charting commit and pull request statistics


# strict mode
set -Eeuo pipefail
IFS=$'\n\t'

# debug mode
#set -o verbose

# define global variables

# script name
readonly script_name=$( echo ${0##*/} | sed 's/\.sh*$//' )

# api host
readonly api_host="api.github.com"

# api protocol
readonly api_protocol="https"

# tool name
readonly tool_name="Git Log Parser"

# get logname
readonly logname=$( logname )

# define fields array
readonly fields=( "Repository" "Hash" "Committer" "Email" "Date" "Comments" )

# format report header
readonly report_header='"'${fields[0]}'","'${fields[1]}'","'${fields[2]}'","'${fields[3]}'","'${fields[4]}'","'${fields[5]}'"'

# format date
readonly report_date=$(date +%Y-%m-%d-%H%M%S)

# path to save report into
readonly report_path=${HOME}'/Projects/'${script_name}

# name of report
readonly report_filename=${script_name}'-'${report_date}'.csv'

# name of database
readonly database_filename=${script_name}'-'${report_date}'.db'

# path of report
readonly report_file=${report_path}'/'${report_filename}

# path of database
readonly database_file=${report_path}'/'${database_filename}


# cleanup working copy
function cleanup() {
    # clean up working copy
    [ -a "${working_file:-}" ] && rm -f ${working_file}
    [ -a "${working_db:-}" ] && rm -f ${working_db}
    dialog --clear

    return

}


# remove temporary files upon trapping SIGHUP/SIGINT/SIGKILL/SIGTERM/SIGEXIT
trap cleanup HUP INT KILL TERM EXIT


# function to catch error messages
# ${1} = error message
# ${2} = exit code
function throw_error() {

    # validate arguments
    if [ ${#} -eq 2 ]; then
        local message=${1}
        local exit_code=${2}

        # log specific error message to syslog and write to STDERR
        logger -s -p user.err -t ${script_name}"["${logname}"]" -- ${message}

        exit ${exit_code}

    else

        # log generic error message to syslog and write to STDERR
        logger -s -p user.err -t ${tool_name}"["${logname}"]" -- "an unknown error occured"

        exit 255

    fi

}


# interpret command-line arguments

# usage
function print_usage() {
    # disable verbosity to enhance readablity
    set +o verbose

    # print usage
    echo -e "\n\nUsage options:"
    echo -e "\t-c | --csv"
    echo -e "\t-f | --token-file <path to token file>"
    echo -e "\t-h | --help"
    echo -e "\t-o | --org-name <github.com organization name>"
    echo -e "\t-s | --sqlite"
    echo -e "\t-t | --token <personal access token>  https://github.com/settings/tokens/new"
    echo -e "\t-q | --quiet"
    echo -e "\t-v | --verbose"
    echo -e "\nExample usage:"
    echo -e "\t"${script_name}".sh --org-name <organization name> --sqlite --csv"
    echo -e "\t"${script_name}".sh --org-name <organization name> --sqlite --quiet"
    echo -e "\t"${script_name}".sh --org-name <organization name> --csv --verbose"
    echo -e "\t"${script_name}".sh --org-name <organization name> --csv --sqlite --token-file ~/"${script_name}".token"
    echo -e "\t"${script_name}".sh --help\n"
    
    return

}


# get formats if not specified as arguments
function get_formats() {
    local -a choice

    # enter interactive mode and prompt user for input
    for choice in $( eval "dialog --shadow --cancel-label \"Quit\" --backtitle \"${tool_name}\" --separate-output --checklist \"Select report format(s):\" 14 40 2 \"csv\" \"Comma-seperated\" ON \"sqlite\" \"Sqlite3 database\" ON" 3>&2 2>&1 1>&3 ); do
        case "${choice}" in
            csv)
                readonly csv_format=1
                ;;

            sqlite)
                readonly sqlite_format=1
                ;;

        esac

    done

}


# get organization name if not specified as argument
function get_organization() {
    # enter interactive mode and prompt user for input
    local choice=$( eval "dialog --shadow --cancel-label \"Quit\" --backtitle \"${tool_name}\" --inputbox \"Please enter an organization name:\" 14 40" 3>&2 2>&1 1>&3 )

    # return in lower case
    echo ${choice,,}

}


# get access token if not specified as argument
function get_token() {
    # enter interactive mode and prompt user for input
    local choice=$( eval "dialog --shadow --cancel-label \"Quit\" --backtitle \"${tool_name}\" --inputbox \"Please enter a personal access token:\n\nGet one here -> https://github.com/settings/tokens/new\" 14 60" 3>&2 2>&1 1>&3 )

    echo ${choice}

}


# validate user-provided organization exists
function validate_organization() {
    local organization=$( curl -s "${api_uri}" | jq -r '.type' )

    [ ${organization,,} == "organization" ] && return 0 || return 1

}


# Transform long options to short ones
for argv in "${@}"; do
    case "${argv}" in
        "--csv")
            set -- "${@}" "-c"
            ;;

        "--help"|"?")
            set -- "${@}" "-h"
            ;;

        "--org-name")
            set -- "${@}" "-o"
            ;;

        "--sqlite")
            set -- "${@}" "-s"
            ;;

        "--token")
            set -- "${@}" "-t"
            ;;
        
        "--token-file")
            set -- "${@}" "-f"
            ;;

        "--quiet")
            set -- "${@}" "-q"
            ;;

        "--verbose")
            set -- "${@}" "-v"
            ;;
        
        *)
            set -- "${@}" "${argv}"
            ;;

    esac

    shift

done


# Parse short options
declare -i OPTIND=1
declare optspec="chfostqv"
while getopts "${optspec}" opt; do
    case $opt in
        "c")
            readonly csv_format=1
            ;;

        "f")
            [ -z ${auth_token:-} ] && readonly auth_token=$( cat ${!OPTIND:-} )
            (( ++OPTIND ))
            ;;

        "h")
            print_usage
            exit 0
            ;;

        "o")
            readonly org_name=${!OPTIND:-}
            (( ++OPTIND ))
            ;;

        "s")
            readonly sqlite_format=1
            ;;

        "t")
            # api oath2 authorization token (get your own => https://github.com/settings/tokens/new)
            [ -z ${auth_token:-} ] && readonly auth_token=${!OPTIND:-}
            (( ++OPTIND ))
            ;;

        "q")
            readonly quiet=1
            ;;

        "v")
            set -o verbose
            ;;

        *)
            print_usage
            exit 1
            ;;

    esac

done

#shift $(expr ${OPTIND} - 1) # remove options from positional parameters


# prompt user to input report format(s) if not specified as argument
if [[ -z ${csv_format:-}  && -z ${sqlite_format:-} ]]; then
    get_formats || throw_error "Unable to set report format" 1

fi

[[ -z ${csv_format:-}  && -z ${sqlite_format:-} ]] && print_usage && throw_error "Report format not specified" 1


# prompt user to input organization name if not specified as argument
if [ -z ${org_name:-} ]; then
    readonly org_name=$( get_organization ) || throw_error "Unable to set organization" 1

fi

[ -z ${org_name:-} ] && print_usage && throw_error "Organization name not specified" 1

# brand name (capitalize org name)
readonly brand_name=${org_name^}

# api uri
readonly api_uri=${api_protocol}"://"${api_host}"/orgs/"${org_name}

# projects path
readonly projects_path=${HOME}'/Projects/'${org_name}

# validate that the orgnization exists prior to going any further
validate_organization || throw_error "Organization ${org_name} does not exist" 1

# prompt user to input personal access token if not specified as argument
if [ -z ${auth_token:-} ]; then
    readonly auth_token=$( get_token ) || throw_error "Unable to set token" 1

fi

[ -z ${auth_token:-} ] && print_usage && throw_error "Personal access token not specified" 1


# create report template
function create_template() {
    if [ ${#} -eq 1 ]; then
        local csv=${1}

        [ -d "${projects_path}" ] && mkdir -p ${projects_path} &>/dev/null
        [ -f "${working_file}" ] && echo ${report_header} > ${csv}

        return ${?}

    fi

}


# append record to report
# ${1} = working file
# ${2} - ${7} = values
function write_report() {
    if [ ${#} -eq 7 ]; then
        local csv=${1}
        local Repository=${2}
        local Hash=${3}
        local Committer=${4}
        local Email=${5}
        local Date=${6}
        local Comments=${7}

        echo -e "\""${Repository}\"","\"${Hash}\"",\""${Committer^}\"",\""${Email}\"",\""${Date}\"",\""${Comments}\" >> ${csv}
        
    fi

}


# create database
function create_database() {
    if [ ${#} -eq 1 ]; then
        local db=${1}

        [ -d "${projects_path}" ] && mkdir -p ${projects_path} &>/dev/null

        # sql create
        sqlite3 ${db} "CREATE TABLE gitlog(ID INTEGER PRIMARY KEY, Repository VARCHAR(100), Hash VARCHAR(10), Committer VARCHAR(255), Email VARCHAR(254), Date DATE, Comments TEXT);" &>/dev/null

    fi

}


# insert into database
# ${1} = database
# ${2} - ${7} = values
function sqlite_insert() {
    if [ ${#} -eq 7 ]; then
        local db=${1}
        local -A values[Repository]=${2}
        local -A values[Hash]=${3}
        local -A values[Committer]=${4}
        local -A values[Email]=${5}
        local -A values[Date]=${6}
        local -A values[Comments]=${7}

        # sql insert
        sqlite3 ${db} "INSERT INTO gitlog(Repository, Hash, Committer, Email, Date, Comments) VALUES (\"${values[Repository]}\", \"${values[Hash]}\", \"${values[Committer]}\", \"${values[Email]}\", \"${values[Date]}\", \"${values[Comments]}\");" &>/dev/null

    else
        return 1

    fi

}


# validate api connectivity
# ${1} = api host
# ${2} = api protocol
function validate_api_connectivity() {
    if [ ${#} -eq 2 ]; then
        # test tcp connectivity on specified host and port
        ( >/dev/tcp/${1}/${2} ) >/dev/null 2>&1
        return ${?}

    else
        return 1

    fi
    
}


# count of private repos
function count_private_repos() {
    # query api for private repository count
    local private_repo_count=$( curl -sH "Authorization: token ${auth_token}" "${api_uri}" | jq -r '.total_private_repos' )

    echo ${private_repo_count}

}


# count of public repos
function count_public_repos() {
    # query api for public repository count
    local public_repo_count=$( curl -sH "Authorization: token ${auth_token}" "${api_uri}" | jq -r '.public_repos' )

    echo ${public_repo_count}

}


# return repository name
# ${1} = page number
function get_repo_name() {
    if [ ${#} -eq 1 ]; then
        # query api for repoistory name
        local repo_name=$( curl -sH "Authorization: token ${auth_token}" "${api_uri}/repos?per_page=1&page=${1}" | jq -r '.[]|.name' )

        echo ${repo_name}

    else
        return 1
        
    fi

}


# clone repository
# ${1} = org name
# ${2} = repository name
function clone_repo() {
    if [ ${#} -eq 2 ]; then
        local org=${1}
        local repo=${2}
        local branch

        cd ${projects_path}
        if [ ! -d ${repo} ]; then
            # clone repository
            git clone --progress git@github.com:${org}/${repo}.git 2>&1 #&>/dev/null

            # enter project directory
            cd ${projects_path}/${repo_name}

            # track all branches
            for branch in $( git branch -a | grep '^  remotes/' | grep -Ev 'HEAD|master' ); do
                git branch --track ${branch#remotes/origin/} 2>&1
            
            done

            # pull all
            git pull --all --progress 2>&1

            # leave project directory
            cd ${projects_path}

        fi

    else
        return 1
        
    fi
    
}


# fetch repositories prior to getting stats
# ${1} = repository name
function fetch_repo() {
    if [ ${#} -eq 1 ]; then
        local repo_name=${1}

        # enter project directory
        cd ${projects_path}/${repo_name}

        # fetch
        git fetch --all --progress 2>&1 #&>/dev/null

        # leave project directory
        cd ${projects_path}

    else
        return 1
        
    fi

}


# merge repositories prior to getting stats
# ${1} = repository name
function merge_repo() {
    if [ ${#} -eq 1 ]; then
        local repo_name=${1}
        local -a local_repo_array=( $(ls -1 ${projects_path}/${repo_name}) )

        # only perform merge if repo is not empty
        if [ ${#local_repo_array[@]} -ne 0 ]; then

            # enter project directory
            cd ${projects_path}/${repo_name}

            # merge
            git merge 2>&1 #&>/dev/null

            # leave project directory
            cd ${projects_path}

        fi

    else
        return 1
        
    fi

}


# export git logs from all repos
# ${1} = repository name
function generate_report() {
    if [ ${#} -eq 1 ]; then
        local repo_name=${1}
        local -a local_repo_array=( $( ls -1 ${projects_path}/${repo_name} ) )
        local -A values
        local eachline onevalue
        
        # only get logs if repo is not empty
        if [ ${#local_repo_array[@]} -ne 0 ]; then
            cd ${projects_path}/${repo_name}

            # iterate over each line of log output, trim away characters we don't want, escape special characters, seperate each field into an associative array
            for eachline in $( 
                git \
                    --no-pager \
                    log \
                    --date='short' \
                    --pretty=format:${repo_name}'|%h|%cn|%ce|%cd|%s' \
                    | tr -d '=;:`"“”&\t\\[]{}()%$' \
                    | sed -e s/\'/\\\\\'/g \
                    | awk -F '|' '{print "declare -A values=(['''${fields[0]}''']=\""$1"\" ['''${fields[1]}''']=\""$2"\" ['''${fields[2]}''']=\""$3"\" ['''${fields[3]}''']=\""$4"\" ['''${fields[4]}''']=\""$5"\" ['''${fields[5]}''']=\""$6"\" )" }' \
                ); do
                
                for onevalue in ${eachline}; do
                    # build ${values[@]} associative array
                    eval "${onevalue}"

                    # display array declaration for debugging
                    #declare -p values

                    # add record to database
                    if [ ! -z ${sqlite_format:-} ]; then
                        sqlite_insert "${working_db}" "${values[${fields[0]}]}" "${values[${fields[1]}]}" "${values[${fields[2]}]^}" "${values[${fields[3]}]}" "${values[${fields[4]}]}" "${values[${fields[5]}]}" || throw_error "Unable to insert "${values[${fields[1]}]}" record" ${?}

                    fi

                    # add line to report
                    if [ ! -z ${csv_format:-} ]; then
                        write_report "${working_file}" "${values[${fields[0]}]}" "${values[${fields[1]}]}" "${values[${fields[2]}]}" "${values[${fields[3]}]}" "${values[${fields[4]}]}" "${values[${fields[5]}]}" || throw_error "Unable to append "${values[${fields[1]}]}" record to report" ${?}

                    fi

                done

            done

            cd ${projects_path}

        fi

    else
        return 1
        
    fi

}


# format report
function normalize_report() {
    if [ ! -z ${csv_format:-} ]; then
        # strip blank lines and rename report
        grep '[^[:blank:]]' < ${working_file} > ${report_file}

    fi


    if [ ! -z ${sqlite_format:-} ]; then
        # copy working db to db file
        cp ${working_db} ${database_file}

    fi

}


# check for dependencies
# ${1} = dependency
function check_dependency() {
    if [ ${#} -eq 1 ]; then
        local dependency=${1}
        local exit_code=${null:-}

        type ${dependency} &>/dev/null; exit_code=${?}
        
        if [ ${exit_code} -ne 0 ]; then
            return 255

        fi

    else
        return 1
        
    fi
    
}


####################
### main program ###
####################

# validate dependencies
readonly -a dependencies=( 'awk' 'dialog' 'git' 'jq' 'logger' 'sed' 'sqlite3' )
declare -i dependency=0

while [ "${dependency}" -lt "${#dependencies[@]}" ]; do
    check_dependency ${dependencies[${dependency}]} || throw_error ${dependencies[${dependency}]}" required" ${?}

    (( ++dependency ))

done

unset dependency


# make sure we're using least bash 4 for proper support of associative arrays
[ $( echo ${BASH_VERSION} | grep -o '^[0-9]' ) -ge 4 ] || throw_error "Please upgrade to at least bash version 4" ${?}

# create template if --csv report was specified
if [ ! -z ${csv_format:-} ]; then
    # temporary working file path
    readonly working_file=$( mktemp -t '.'${report_filename} )

    create_template ${working_file} || throw_error "Unable to create template" ${?}

fi

# Create database if sqlite format was specified 
if [ ! -z ${sqlite_format:-} ]; then
    # temporary database path
    readonly working_db=$( mktemp -t '.'${database_filename} )

    create_database ${working_db} || throw_error "Unable to create database" ${?}

fi

# display loading dialog
[ -z ${quiet:-} ] && dialog --keep-window --shadow --backtitle "${brand_name} - ${tool_name}" --infobox "Loading "${org_name}" repositories..." 3 50

# get count of public repositories
public_repo_count=$(count_public_repos) || throw_error "Unable to get count of public repositories for "${org_name}" organization" ${?}

# get count of private repositories
private_repo_count=$(count_private_repos) || throw_error "Unable to get count of private repositories for "${org_name}" organization" ${?}

# calculate total repository count
total_repo_count=$(( public_repo_count + private_repo_count ))

# begin main loop
declare -i index=1
declare -i new_repo_count=0
while [ "${index}" -lt "${total_repo_count}" ]; do
    validate_api_connectivity ${api_host} ${api_protocol} || throw_error "Unable to establish tcp connection to "${api_host} ${?}
    repo_name=$(get_repo_name ${index}) || throw_error "Unable to get repo name" ${?}

    # if repository doesn't exist locally, clone it
    if [ ! -d ${projects_path}/${repo_name} ]; then
        # Cloning repo
        # if [ -z ${quiet:-} ]; then
        #     clone_repo ${org_name} ${repo_name} &> >(dialog --shadow --backtitle "${brand_name} - ${tool_name}" --progressbox "Cloning ${repo_name}" 20 60) || throw_error "Unable to clone "${repo_name} ${?}

        # else
            clone_repo ${org_name} ${repo_name} &>/dev/null || throw_error "Unable to clone "${repo_name} ${?}

        # fi

        (( ++new_repo_count ))

    # fetch existing repository
    else
        # Fetching repo
        # if [ -z ${quiet:-} ]; then
            
        #     fetch_repo ${repo_name} &> >(dialog --shadow --backtitle "${brand_name} - ${tool_name}" --progressbox "Fetching ${repo_name}" 20 60) || throw_error "Unable to fetch "${repo_name} ${?}

        #     # this isn't reasonably safe to do
        #     #merge_repo ${repo_name} &> >(dialog --shadow --backtitle "${brand_name} - ${tool_name}" --progressbox "Merging ${repo_name}" 20 60) || throw_error "Unable to merge "${repo_name} ${?}

        # else
            fetch_repo ${repo_name} &>/dev/null || throw_error "Unable to fetch "${repo_name} ${?}

        #     #merge_repo ${repo_name} &>/dev/null || throw_error "Unable to merge "${repo_name} ${?}

        # fi

    fi


    # render progress bar dialog
    [ -z ${quiet:-} ] && awk -v STEP="${index}" -v COUNT="${total_repo_count}" 'BEGIN {printf "%d\n", ((STEP / (COUNT -1)) * 100)}' | dialog --keep-window --backtitle "${brand_name} - ${tool_name}" --no-shadow --cancel-label "Cancel" --gauge "Parsing ${repo_name} repository (${index} of ${total_repo_count})" 6 76 0

    # Parsing git log for
    generate_report ${repo_name} || throw_error "Unable to parse git log for "${repo_name} ${?}
    
    (( ++index ))

done

unset index


# Writing report
normalize_report || throw_error "Unable to normalize report" ${?}

# Count records
if [ ! -z ${csv_format:-} ]; then
    record_count=$( cat ${report_file} | grep -c '^' )
    (( --record_count )) # subtract headers

fi


if [ ! -z ${sqlite_format:-} ]; then
    record_count=$( sqlite3 ${database_file} "SELECT COUNT(*) FROM gitlog;" )

fi


# Display post-run status dialog if not running in quiet mode
if [ -z ${quiet:-} ]; then
    dialog --shadow --clear --backtitle "${brand_name} - ${tool_name}" --msgbox "${new_repo_count} new ${org_name} repositories cloned\n${public_repo_count} public ${org_name} repositories\n${private_repo_count} private ${org_name} repositories\n\n${total_repo_count} total ${org_name} repositories\n\n${record_count} logs parsed" 12 50
    
    # clear the dialog off the screen
    clear

else
    echo -e "${new_repo_count} new ${org_name} repositories cloned\n${public_repo_count} public ${org_name} repositories\n${private_repo_count} private ${org_name} repositories\n\n${total_repo_count} total ${org_name} repositories\n\n${record_count} logs parsed"

fi


# Cleaning up temporary files
cleanup || throw_error "Unable to clean up temporary files" ${?}