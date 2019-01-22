#!/bin/bash

usage() {
	local old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${name} - Generate TDD iPXE boot scripts and build iPXE images." >&2
	echo "Usage: ${name} [flags]" >&2
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
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${name}" -- "$@")

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
				echo "${name}: ERROR: Got extra args: '${@}'" >&2
				usage
				exit 1
			fi
			break
			;;
		*)
			echo "${name}: ERROR: Internal opts: '${@}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	set +x
	echo "${name}: Done:       ${result}" >&2
}

check_file() {
	local src="${1}"
	local msg="${2}"
	local usage="${3}"

	if [[ ! -f "${src}" ]]; then
		echo -e "${name}: ERROR: File not found${msg}: '${src}'" >&2
		[[ -z "${usage}" ]] || usage
		exit 1
	fi
}

process() {
	rm -f "${output_dir}"/ipxe-tdd-${host}.boot-script
	cp -f "${SCRIPTS_TOP}"/tdd-boot-script.in "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@HOST@|${host}|g" "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@TFTP_SERVER@|${tftp_server}|g" "${output_dir}"/tdd-boot-script.tmp
	sed --in-place "s|@IF_CONFIG@|${host_if_config}|" "${output_dir}"/tdd-boot-script.tmp
	mv -f "${output_dir}"/tdd-boot-script.tmp "${output_dir}"/ipxe-tdd-${host}.boot-script

	if [[ ! ${boot_scripts} ]]; then
		make -C ${src_dir} ${make_extra} \
			CROSS_COMPILE=aarch64-linux-gnu- \
			ARCH=arm64 \
			EMBED="${output_dir}"/ipxe-tdd-${host}.boot-script \
			-j $(getconf _NPROCESSORS_ONLN || echo 1) \
			bin-arm64-efi/snp.efi
		cp ${src_dir}/bin-arm64-efi/snp.efi ${output_dir}/ipxe-tdd-${host}.efi
	fi
}

#===============================================================================
# program start
#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
set -e

name="${0##*/}"
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
	echo "${name}: ERROR: No machines array: '${config_file}'" >&2
	exit 1
fi

echo "machines_static count = ${#machines_static[@]}" >&2
echo "machines_dhcp count = ${#machines_dhcp[@]}" >&2

if [[ ${verbose} ]]; then
	make_extra="V=1"
fi

rm -rf ${output_dir}
mkdir -p ${output_dir}

if [[ ! ${boot_scripts} ]]; then
	make -C ${src_dir} veryclean
	make -C ${src_dir} ${make_extra} \
		CROSS_COMPILE=aarch64-linux-gnu- \
		ARCH=arm64 \
		-j $(getconf _NPROCESSORS_ONLN || echo 1) \
		bin-arm64-efi/snp.efi
	cp ${src_dir}/bin-arm64-efi/snp.efi ${output_dir}/ipxe-tdd-generic.efi
fi

for m in "${machines_static[@]}"; do
	echo "static: @${m}@" >&2

# "test	1a:2b:3c:4d:5e:6f	192.168.1.2	255.255.255.0	192.168.1.1	192.168.1.3"

	unset host mac_addr ip_addr netmask gateway tftp_server

	regex_host="^([[:alnum:]]*-*[[:alnum:]]*)[[:space:]]"
	[[ "${m}" =~ ${regex_host} ]] && host="${BASH_REMATCH[1]}"

	regex_mac="[[:space:]]([[:xdigit:]]{2}(:[[:xdigit:]]{2}){5})[[:space:]]"
	[[ "${m}" =~ ${regex_mac} ]] && mac_addr="${BASH_REMATCH[1]}"

	regex_ip="[[:space:]]([[:digit:]]{1,3}(\.[[:digit:]]{1,3}){3})"
	regex="${regex_ip}${regex_ip}${regex_ip}${regex_ip}$"
	if [[ "${m}" =~ ${regex} ]]; then
		ip_addr="${BASH_REMATCH[1]}"
		netmask="${BASH_REMATCH[3]}"
		gateway="${BASH_REMATCH[5]}"
		tftp_server="${BASH_REMATCH[7]}"
	fi

	echo "host        = @${host}@" >&2
	echo "mac_addr    = @${mac_addr}@" >&2
	echo "ip_addr     = @${ip_addr}@" >&2
	echo "netmask     = @${netmask}@" >&2
	echo "gateway     = @${gateway}@" >&2
	echo "tftp_server = @${tftp_server}@" >&2

	if [[ ! "${host}" ]]; then
		echo "${name}: ERROR: Bad host config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${mac_addr}" ]]; then
		echo "${name}: ERROR: Bad mac_addr config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${ip_addr}" ]]; then
		echo "${name}: ERROR: Bad ip_addr config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${netmask}" ]]; then
		echo "${name}: ERROR: Bad netmask config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${gateway}" ]]; then
		echo "${name}: ERROR: Bad gateway config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${tftp_server}" ]]; then
		echo "${name}: ERROR: Bad tftp_server config: '${m}'" >&2
		exit 1
	fi

	server_addr="$(dig ${tftp_server} +short)"

	if [[ ${server_addr} ]]; then
		tftp_server=${server_addr}
	fi

	host_if_config="ifclose ; set net0/mac ${mac_addr} ; set net0/ip ${ip_addr} ; set net0/netmask ${netmask} ; set net0/gateway ${gateway} ; ifopen net0"

	process
done

for m in "${machines_dhcp[@]}"; do
	echo "dhcp: @${m}@" >&2

	unset host tftp_server

	regex_host="^([[:alnum:]]*-*[[:alnum:]]*)[[:space:]]"
	[[ "${m}" =~ ${regex_host} ]] && host="${BASH_REMATCH[1]}"

	regex_ip="[[:space:]]([[:digit:]]{1,3}(\.[[:digit:]]{1,3}){3})"
	regex="${regex_ip}$"
	if [[ "${m}" =~ ${regex} ]]; then
		tftp_server="${BASH_REMATCH[1]}"
	fi

	echo "host        = @${host}@" >&2
	echo "tftp_server = @${tftp_server}@" >&2

	if [[ ! "${host}" ]]; then
		echo "${name}: ERROR: Bad host config: '${m}'" >&2
		exit 1
	fi

	if [[ ! "${tftp_server}" ]]; then
		echo "${name}: ERROR: Bad tftp_server config: '${m}'" >&2
		exit 1
	fi

	server_addr="$(dig ${tftp_server} +short)"

	if [[ ${server_addr} ]]; then
		tftp_server=${server_addr}
	fi

	host_if_config="ifconf"

	process
done

trap - EXIT
on_exit 'Done, success.'
echo "${name}: Output in: ${output_dir}" >&2
