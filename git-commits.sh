#!/usr/bin/env bash

# This tool was written to parse git logs to generate a report for charting commit and pull request statistics

projects_path=${HOME}"/Projects"
repo_array=( $(ls -1 ${projects_path}) )
repo_array_count=${#repo_array[@]}
report_header='"Repository","Hash","Comitter","Email","Date","Comments"'
report_date=$(date +%Y-%m-%d)
report_path=${projects_path}"/git-commits"
report_filename='git-commits-'${report_date}'.csv'
report_file=${report_path}'/'${report_filename}
working_file=$( mktemp -t '.'${report_filename}'-' )


# create report template
function create_template() {
    mkdir -p ${projects_path} >/dev/null 2>&1
    echo ${report_header} > ${working_file}

}


# update repositories prior to getting stats
function update_repo() {
    local repo_name=${1}
        
    cd ${projects_path}/${repo_name}
    git fetch >/dev/null 2>&1
    cd ${projects_path}

}


# export git logs from all repos
function generate_report() {
    local repo_name=${1}

    cd ${projects_path}/${repo_name}
    git log --since='01/01/2018' --date='short' --pretty=format:'"'${repo_name}'","%h","%cn","%ce","%cd","%s"' | tee -a ${working_file} >/dev/null 2>&1
    echo "" >> ${working_file}
    cd ${projects_path}

}


# format report
function normalize_report() {
    # strip blank lines and rename report
    grep '[^[:blank:]]' < ${working_file} > ${report_file}

    # clean up working copy
    rm ${working_file}

}


### MAIN
create_template

index=0 && while [ ${index} -lt ${repo_array_count} ]; do
    echo 'Fetching '${repo_array[${index}]}
    update_repo ${repo_array[${index}]}

    echo 'Parsing git log for '${repo_array[${index}]}
    generate_report ${repo_array[${index}]}

    (( index++ ))

done

normalize_report