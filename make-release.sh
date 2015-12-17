#!/bin/bash

cwd=$(pwd)

STAGING_DIR="staging"

#REPO_LOCAL_DIR="staging/${REPO_LOCAL_DIR}"

source ./config.conf

#define the template.
function generate_platform_template() #version, url, checksum, size
{

local archiveFileName="${2}"; 

local ARDUINO_PLATFORM_TEMPLATE_JSON=`cat<<EOF
			{
				"name" : "${BOARD_NAME}",
				"architecture" : "${BOARD_ARCH}",
				"version" : "${1}",
				"category" : "${BOARD_CATEGORY}",
				"url" : "${2}",
				"archiveFileName" : "${archiveFileName##*/}",
				"checksum" : "SHA-256:${3}",
				"size" : "${4}",
				"help" : {
					"online" : "${BOARD_HELP_URL}"
				},
				"boards" : [
					{
						"name" : "${BOARD_NAME}"
					}
				],
				"toolsDependencies" : [
					{
						"packager" : "arduino",
						"name" : "avr-gcc",
						"version" : "4.8.1-arduino5"
					},
					{
						"packager" : "arduino",
						"name" : "avrdude",
						"version" : "6.0.1-arduino5"
					}
				]
			}
EOF`
echo "${ARDUINO_PLATFORM_TEMPLATE_JSON}"
}


function generate_package_template() #platforms
{
local ARDUINO_PACKAGES_TEMPLATE_JSON=`cat<<EOF
{
	"packages" : [
		{
			"name" : "${BOARD_PACKAGE_NAME}",
			"maintainer" : "${BOARD_PACKAGE_MAINTAINER}",
			"websiteURL" : "${BOARD_PACKAGE_WEB_URL}",
			"email" : "${BOARD_PACKAGE_MAINTAINER_EMAIL}",
			"help" : {
				"online" : "${BOARD_PACKAGE_HELP_URL}"
			},
			"platforms" : [
				${1}
			],
			"tools" : []
		}
	]
}
EOF`	
echo "${ARDUINO_PACKAGES_TEMPLATE_JSON}"
}

function git_update_repo()
{
	if [ -d "${STAGING_DIR}/${REPO_LOCAL_DIR}" ] #if directory exists
	then
		cd "${cwd}/${STAGING_DIR}/${REPO_LOCAL_DIR}"

		git fetch --all
		git pull --all

#		for b in `git branch -r | grep -v -- '->'`; 
#		do 
#			echo "${b}"
#			#git branch --track ${b##origin/} $b; 
#		done

	fi
	
	cd "${cwd}"
}

function update_release_repo() #repo url, dir, specific commit
{
	local _REPO_REMOTE_URL=${1}
	local _REPO_LOCAL_DIR=${2}
	local _COMMIT_HASH=${3}
	
	if [ -d "${_REPO_LOCAL_DIR}" ] #if directory exists
	then
		cd "${cwd}/${_REPO_LOCAL_DIR}"
		git checkout ${_COMMIT_HASH}
		git submodule update --init --recursive
	else
		git clone "${_REPO_REMOTE_URL}" "${_REPO_LOCAL_DIR}"
		cd "${_REPO_LOCAL_DIR}"
		git checkout ${_COMMIT_HASH}
		git submodule update --init --recursive
	fi
	
	cd "${cwd}"
}


function archive_release_repo() #repo dir, filename
{
	local _REPO_DIR=${1}
	local _ARCHIVE_FILE=${2}
	
	cd ${cwd}/${_REPO_DIR}
	tar --exclude=".git" --exclude="make_package.sh" --exclude=".DS_Store" --exclude=".gitignore" --exclude=".gitmodules" --exclude="package_babygnusbuino2_index.json" -czf  ${cwd}/${RELEASES_DIR}/${_ARCHIVE_FILE}.tar.gz  *
	shasum -a 256 ${cwd}/${RELEASES_DIR}/${_ARCHIVE_FILE}.tar.gz  | cut -d ' ' -f 1 > ${cwd}/${RELEASES_DIR}/${_ARCHIVE_FILE}.sha.txt
	cd "${cwd}"
}


function check_release_archive_exists()
{
	local _FILE_NAME=${1}
	
	if [ -e "${cwd}/${RELEASES_DIR}/${_FILE_NAME}.tar.gz" ]
	then
		return 0 #true
	else
		return 1 #false
	fi
}


function make_packages()
{
	#git_update_repo
	
	local input="releases.txt"
	local platform_list=""
	local releases=()

	while IFS= read -r var
	do
		IFS=', ' read -r line <<< "$var"
		releases+=(${line})
	done < "$input"

	# get length of an array
	tLen=${#releases[@]}
	 
	# use for loop read all
	for (( i=0; i<${tLen}; i++ ));
	do
  		IFS=', ' read -a array <<< "${releases[$i]}"
		local _RELEASE_VERSION=${array[0]}
		local _COMMIT_HASH=${array[1]}

		if check_release_archive_exists ${RELEASE_PREFIX}${_RELEASE_VERSION}
		then
			echo "${_RELEASE_VERSION} exists, skip"
		else
			update_release_repo "${REPO_URL}" "${STAGING_DIR}/${REPO_LOCAL_DIR}" "${_COMMIT_HASH}"
			archive_release_repo "${STAGING_DIR}/${REPO_LOCAL_DIR}" "${RELEASE_PREFIX}${_RELEASE_VERSION}"
		fi	

		local sha_result=`shasum -a 256 ${cwd}/${RELEASES_DIR}/${RELEASE_PREFIX}${_RELEASE_VERSION}.tar.gz | cut -d ' ' -f 1`
		platform_list+=`generate_platform_template ${_RELEASE_VERSION} ${BOARD_ARCHIVE_URL}/${RELEASE_PREFIX}${_RELEASE_VERSION}.tar.gz ${sha_result}`
		
		if [ $((i+1)) -ne $tLen ]
		then
			platform_list+=",\n"
		fi
	done

	local json_package_output=`generate_package_template "${platform_list}"`
	echo "${json_package_output}" > "${RELEASE_INDEX_JSON_FILENAME}"
}


make_packages


