#!/bin/bash

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - Generate TDD iPXE boot scripts and build iPXE images." >&2
	echo "Usage: ${script_name} [flags]" >&2
	echo "Option flags:" >&2
	echo "  -b --boot-scripts - Only generate boot scripts. Default: '${boot_scripts}'." >&2
	echo "  -c --config-file  - Config file. Default: '${config_file}'." >&2
	echo "  -h --help         - Show this help and exit." >&2
	echo "  -o --output-dir   - Output directory. Default: '${output_dir}'." >&2
	echo "  -v --verbose      - Verbose execution." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="bc:ho:v"
	local long_opts="boot-scripts,config-file:,help,output-dir:,verbose"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		case "${1}" in
		-b | --boot-scripts)
			boot_scripts=1
			shift
			;;
		-c | --config-file)
			config_file="${2}"
			shift 2
			;;
		-h | --help)
			usage=1
			shift
			;;
		-o | --output-dir)
			output_dir="${2}"
			shift 2
			;;
		-v | --verbose)
			set -x
			verbose=1
			shift
			;;
		--)
			shift
			if [[ -n "${1}" ]]; then
				echo "${script_name}: ERROR: Got extra args: '${@}'" >&2
				usage
				exit 1
			fi
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${@}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	set +x
	echo "${script_name}: Done:       ${result}" >&2
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${script_name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

build_image() {
	local host=${1}
	local arch=${2}

	echo "${FUNCNAME[0]}: ${host}-${arch}" >&2

	if [[ "${host}" == "generic" ]]; then
		unset build_extra
	else
		build_extra="EMBED='${output_dir}/ipxe-tdd-${host}.boot-script'"
	fi

	case "${arch}" in
	amd64 | x86_64)
		if ! test -x "$(command -v "x86_64-linux-gnu-gcc")"; then
			echo "${script_name}: ERROR: Please install 'x86_64-linux-gnu-gcc'." >&2
			exit 1
		fi
		eval "make -C ${src_dir} ${make_extra} \
			CROSS_COMPILE=x86_64-linux-gnu- \
			ARCH=x86_64 \
			${build_extra} \
			-j $(getconf _NPROCESSORS_ONLN || echo 1) \
			bin-x86_64-efi/snp.efi"
		cp ${src_dir}/bin-x86_64-efi/snp.efi ${output_dir}/ipxe-tdd-${host}.efi
		;;
	arm64)
		if ! test -x "$(command -v "aarch64-linux-gnu-gcc")"; then
			echo "${script_name}: ERROR: Please install 'aarch64-linux-gnu-gcc'." >&2
			exit 1
		fi
		eval "make -C ${src_dir} ${make_extra} \
			CROSS_COMPILE=aarch64-linux-gnu- \
			ARCH=arm64 \
			${build_extra} \
			-j $(getconf _NPROCESSORS_ONLN || echo 1) \
			bin-arm64-efi/snp.efi"
		cp ${src_dir}/bin-arm64-efi/snp.efi ${output_dir}/ipxe-tdd-${host}.efi
		;;
	*)
		echo "${script_name}: ERROR: Unsupported host arch '${arch}'." >&2
		exit 1
	esac
}

process() {
	rm -f "${output_dir}"/ipxe-tdd-${host}.boot-script
	cp -f "${SCRIPTS_TOP}"/tdd-boot-script.in "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@HOST@|${host}|g" "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@TFTP_SERVER@|${tftp_server}|g" "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@IF_CONFIG@|${host_if_config}|" "${output_dir}"/tdd-boot-script.tmp
	mv -f "${output_dir}"/tdd-boot-script.tmp "${output_dir}"/ipxe-tdd-${host}.boot-script

	if [[ ! ${boot_scripts} ]]; then
		need_generic["${arch}"]=1
		build_image "${host}" "${arch}"
	fi
}

parse_static() {
	# "test1 powerpc 1a:2b:3c:4d:5e:6f 192.168.1.2 255.255.255.0 192.168.1.1 192.168.1.3"

	for m in "${machines_static[@]}"; do
		unset host arch mac_addr ip_addr netmask gateway tftp_server

		echo "static: '${m}'" >&2

		# host
		regex="^${regex_word}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			host="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad host config: '${m}'" >&2
			exit 1
		fi

		echo " host        = '${host}'" >&2
		m="${m#${host}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# arch
		regex="^${regex_word}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			arch="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad arch config: '${m}'" >&2
			exit 1
		fi

		echo " arch        = '${arch}'" >&2
		m="${m#${arch}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# mac_addr
		regex="^${regex_mac}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			mac_addr="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad mac_addr config: '${m}'" >&2
			exit 1
		fi

		echo " mac_addr    = '${mac_addr}'" >&2
		m="${m#${mac_addr}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# ip_addr
		regex="^${regex_ip}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			ip_addr="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad ip_addr config: '${m}'" >&2
			exit 1
		fi

		echo " ip_addr     = '${ip_addr}'" >&2
		m="${m#${ip_addr}}"
		m="${m#"${m%%[![:space:]]*}"}"
		
		# netmask
		regex="^${regex_ip}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			netmask="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad netmask config: '${m}'" >&2
			exit 1
		fi

		echo " netmask     = '${netmask}'" >&2
		m="${m#${netmask}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# gateway
		regex="^${regex_ip}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			gateway="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad gateway config: '${m}'" >&2
			exit 1
		fi

		echo " gateway     = '${gateway}'" >&2
		m="${m#${gateway}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# tftp_server
		regex="^${regex_ip}[[:space:]]*$"
		if [[ "${m}" =~ ${regex} ]]; then
			tftp_server="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad tftp_server config: '${m}'" >&2
			exit 1
		fi

		echo " tftp_server = '${tftp_server}'" >&2
		m="${m#${tftp_server}}"
		m="${m#"${m%%[![:space:]]*}"}"

		server_addr="$(dig ${tftp_server} +short)"

		if [[ ${server_addr} ]]; then
			tftp_server=${server_addr}
		fi

		host_if_config="ifclose ; set net0/mac ${mac_addr} ; set net0/ip ${ip_addr} ; set net0/netmask ${netmask} ; set net0/gateway ${gateway} ; ifopen net0"

		process
	done
}

parse_dhcp() {
	# "test2 arm64 192.168.1.4"

	for m in "${machines_dhcp[@]}"; do
		unset host tftp_server

		echo "dhcp: '${m}'" >&2

		# host
		regex="^${regex_word}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			host="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad host config: '${m}'" >&2
			exit 1
		fi

		echo " host        = '${host}'" >&2
		m="${m#${host}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# arch
		regex="^${regex_word}[[:space:]]+"
		if [[ "${m}" =~ ${regex} ]]; then
			arch="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad arch config: '${m}'" >&2
			exit 1
		fi

		echo " arch        = '${arch}'" >&2
		m="${m#${arch}}"
		m="${m#"${m%%[![:space:]]*}"}"

		# tftp_server
		regex="^${regex_ip}[[:space:]]*$"
		if [[ "${m}" =~ ${regex} ]]; then
			tftp_server="${BASH_REMATCH[1]}"
		else
			echo "${script_name}: ERROR: Bad tftp_server config: '${m}'" >&2
			exit 1
		fi

		echo " tftp_server = '${tftp_server}'" >&2
		m="${m#${tftp_server}}"
		m="${m#"${m%%[![:space:]]*}"}"

		server_addr="$(dig ${tftp_server} +short)"

		if [[ ${server_addr} ]]; then
			tftp_server=${server_addr}
		fi

		host_if_config="ifconf"

		process
	done
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -e

script_name="${0##*/}"
SCRIPTS_TOP=${SCRIPTS_TOP:-"$(cd "${BASH_SOURCE%/*}" && pwd)"}
src_dir=${SCRIPTS_TOP}

trap "on_exit 'failed.'" EXIT

process_opts "${@}"

output_dir=${output_dir:-"$(pwd)"}
output_dir+="/ipxe-out-$(date +%Y.%m.%d-%H.%M.%S)"

config_file="${config_file:-${SCRIPTS_TOP}/ipxe-image.conf}"

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

check_file ${config_file} " --config-file" "usage"
source ${config_file}

if [[ ! "${machines_static[@]}" && ! "${machines_dhcp[@]}" ]]; then
	echo "${script_name}: ERROR: No machines array: '${config_file}'" >&2
	exit 1
fi

echo "machines_static count = ${#machines_static[@]}" >&2
echo "machines_dhcp count = ${#machines_dhcp[@]}" >&2

if [[ ${verbose} ]]; then
	make_extra="V=1"
fi

rm -rf ${output_dir}
mkdir -p ${output_dir}

declare -A need_generic

regex_word="([^[:space:]]+)"
regex_mac="([[:xdigit:]]{2}(:[[:xdigit:]]{2}){5})"
regex_ip="([[:digit:]]{1,3}(\.[[:digit:]]{1,3}){3})"

if [[ ! ${boot_scripts} ]]; then
	make -C ${src_dir} veryclean
fi

parse_static
parse_dhcp

if [[ ! ${boot_scripts} ]]; then
	for a in ${!need_generic[@]}; do
		echo "need_generic = '${a}'" >&2
		build_image "generic" "${arch}"
	done
fi

trap - EXIT
on_exit 'Done, success.'
echo "${script_name}: Output in: ${output_dir}" >&2
