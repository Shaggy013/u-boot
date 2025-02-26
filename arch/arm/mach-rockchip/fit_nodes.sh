#!/bin/bash
#
# Copyright (C) 2021 Rockchip Electronics Co., Ltd
#
# SPDX-License-Identifier:     GPL-2.0+
#

# Process args and auto set variables
source ./${srctree}/arch/arm/mach-rockchip/fit_args.sh
rm -f ${srctree}/*.digest ${srctree}/*.bin.gz ${srctree}/bl31_0x*.bin

# compression
if [ "${COMPRESSION}" == "gzip" ]; then
	SUFFIX=".gz"
	CMD="gzip"
elif [ "${COMPRESSION}" == "lzma" ]; then
	SUFFIX=".lzma"
	CMD="lzma"
else
	COMPRESSION="none"
	SUFFIX=
fi

# nodes
function gen_uboot_node()
{
	UBOOT="u-boot-nodtb.bin"
	echo "		uboot {
			description = \"U-Boot\";
			data = /incbin/(\"${UBOOT}${SUFFIX}\");
			type = \"standalone\";
			arch = \"${U_ARCH}\";
			os = \"U-Boot\";
			compression = \"${COMPRESSION}\";
			load = <"${UBOOT_LOAD_ADDR}">;"
	if [ "${COMPRESSION}" != "none" ]; then
		openssl dgst -sha256 -binary -out ${UBOOT}.digest ${UBOOT}
		UBOOT_SZ=`ls -l ${UBOOT} | awk '{ print $5 }'`
		RAW_SIZE=`wc -c ${UBOOT} | awk '{ printf "0x%x", $1 }'`
		if [ ${UBOOT_SZ} -gt 0 ]; then
			${CMD} -k -f -9 ${srctree}/${UBOOT}
		else
			touch ${srctree}/${UBOOT}${SUFFIX}
		fi
		echo "			raw-size = <${RAW_SIZE}>;
			digest {
				value = /incbin/(\"./${UBOOT}.digest\");
				algo = \"sha256\";
			};"
	fi
	echo "			hash {
				algo = \"sha256\";
			};
		};"
}

function gen_fdt_node()
{
	echo "		fdt {
			description = \"U-Boot dtb\";
			data = /incbin/(\"./u-boot.dtb\");
			type = \"flat_dt\";
			arch = \"${U_ARCH}\";
			compression = \"none\";
			hash {
				algo = \"sha256\";
			};
		};"
};

function gen_kfdt_node()
{
	KERN_DTB=`sed -n "/CONFIG_EMBED_KERNEL_DTB_PATH=/s/CONFIG_EMBED_KERNEL_DTB_PATH=//p" .config | tr -d '"'`
	if [ -z "${KERN_DTB}" ]; then
		return;
	fi

	if [ -f ${srctree}/${KERN_DTB} ]; then
	PROP_KERN_DTB=', "kern-fdt"';
	echo "		kern-fdt {
			description = \"${KERN_DTB}\";
			data = /incbin/(\"${KERN_DTB}\");
			type = \"flat_dt\";
			arch = \"${U_ARCH}\";
			compression = \"none\";
			hash {
				algo = \"sha256\";
			};
		};"
	fi
}

function gen_bl31_node()
{
	${srctree}/arch/arm/mach-rockchip/decode_bl31.py

	NUM=1
	for ATF in `ls -l bl31_0x*.bin | sort --key=5 -nr | awk '{ print $9 }'`
	do
		ATF_LOAD_ADDR=`echo ${ATF} | awk -F "_" '{ printf $2 }' | awk -F "." '{ printf $1 }'`
		# only atf-1 support compress
		if [ "${COMPRESSION}" != "none" -a ${NUM} -eq 1  ]; then
			openssl dgst -sha256 -binary -out ${ATF}.digest ${ATF}
			${CMD} -k -f -9 ${ATF}

			echo "		atf-${NUM} {
			description = \"ARM Trusted Firmware\";
			data = /incbin/(\"./${ATF}${SUFFIX}\");
			type = \"firmware\";
			arch = \"${ARCH}\";
			os = \"arm-trusted-firmware\";
			compression = \"${COMPRESSION}\";
			load = <"${ATF_LOAD_ADDR}">;
			hash {
				algo = \"sha256\";
			};
			digest {
				value = /incbin/(\"./${ATF}.digest\");
				algo = \"sha256\";
			};
		};"
		else
			echo "		atf-${NUM} {
			description = \"ARM Trusted Firmware\";
			data = /incbin/(\"./${ATF}\");
			type = \"firmware\";
			arch = \"${ARCH}\";
			os = \"arm-trusted-firmware\";
			compression = \"none\";
			load = <"${ATF_LOAD_ADDR}">;
			hash {
				algo = \"sha256\";
			};
		};"
		fi

		if [ ${NUM} -gt 1 ]; then
			LOADABLE_ATF=${LOADABLE_ATF}", \"atf-${NUM}\""
		fi
		NUM=`expr ${NUM} + 1`
	done
}

function gen_bl32_node()
{
	if [ -z ${TEE_LOAD_ADDR} ]; then
		return
	fi

	if [ "${ARCH}" == "arm" ]; then
		# If not AArch32 mode
		if ! grep  -q '^CONFIG_ARM64_BOOT_AARCH32=y' .config ; then
			ENTRY="entry = <0x${TEE_LOAD_ADDR}>;"
		fi
	fi

	TEE="tee.bin"
	echo "		optee {
			description = \"OP-TEE\";
			data = /incbin/(\"${TEE}${SUFFIX}\");
			type = \"firmware\";
			arch = \"${ARCH}\";
			os = \"op-tee\";
			compression = \"${COMPRESSION}\";
			${ENTRY}
			load = <"0x${TEE_LOAD_ADDR}">;"
	if [ "${COMPRESSION}" != "none" ]; then
		RAW_SIZE=`wc -c ${TEE} | awk '{ printf "0x%x", $1 }'`
		openssl dgst -sha256 -binary -out ${TEE}.digest ${TEE}
		${CMD} -k -f -9 ${TEE}
		echo "			raw-size = <${RAW_SIZE}>;
			digest {
				value = /incbin/(\"./${TEE}.digest\");
				algo = \"sha256\";
			};"
	fi
	echo "			hash {
				algo = \"sha256\";
			};
		};"
	LOADABLE_OPTEE=", \"optee\""
}

function gen_mcu_node()
{
	for ((i=0, n=0; i<5; i++))
	do
		if [ ${i} -eq 0 ]; then
			MCU_ADDR=${MCU0_LOAD_ADDR}
		elif [ ${i} -eq 1 ]; then
			MCU_ADDR=${MCU1_LOAD_ADDR}
		elif [ ${i} -eq 2 ]; then
			MCU_ADDR=${MCU2_LOAD_ADDR}
		elif [ ${i} -eq 3 ]; then
			MCU_ADDR=${MCU3_LOAD_ADDR}
		elif [ ${i} -eq 4 ]; then
			MCU_ADDR=${MCU4_LOAD_ADDR}
		fi

		if [ -z ${MCU_ADDR} ]; then
			continue
		fi
		MCU="mcu${i}"
		echo "		${MCU} {
			description = \"${MCU}\";
			type = \"standalone\";
			arch = \"riscv\";
			data = /incbin/(\"./${MCU}.bin${SUFFIX}\");
			compression = \"${COMPRESSION}\";
			load = <0x"${MCU_ADDR}">;"
		if [ "${COMPRESSION}" != "none" ]; then
			openssl dgst -sha256 -binary -out ${MCU}.bin.digest ${MCU}.bin
			${CMD} -k -f -9 ${MCU}.bin
			RAW_SIZE=`wc -c ${MCU}.bin | awk '{ printf "0x%x", $1 }'`
		echo "			raw-size = <${RAW_SIZE}>;
			digest {
				value = /incbin/(\"./${MCU}.bin.digest\");
				algo = \"sha256\";
			};"
		fi
		echo "			hash {
				algo = \"sha256\";
			};
		};"

		if [ ${n} -eq 0 ]; then
			STANDALONE_LIST=${STANDALONE_LIST}"\"${MCU}\""
		else
			STANDALONE_LIST=${STANDALONE_LIST}", \"${MCU}\""
		fi
		n=`expr ${n} + 1`

		STANDALONE_SIGN=", \"standalone\""
		STANDALONE_MCU="standalone = ${STANDALONE_LIST};"
	done
}

function gen_loadable_node()
{
	for ((i=0; i<5; i++))
	do
		if [ ${i} -eq 0 ]; then
			LOAD_ADDR=${LOAD0_LOAD_ADDR}
		elif [ ${i} -eq 1 ]; then
			LOAD_ADDR=${LOAD1_LOAD_ADDR}
		elif [ ${i} -eq 2 ]; then
			LOAD_ADDR=${LOAD2_LOAD_ADDR}
		elif [ ${i} -eq 3 ]; then
			LOAD_ADDR=${LOAD3_LOAD_ADDR}
		elif [ ${i} -eq 4 ]; then
			LOAD_ADDR=${LOAD4_LOAD_ADDR}
		fi

		if [ -z ${LOAD_ADDR} ]; then
			continue
		fi
		LOAD="load${i}"
		echo "		${LOAD} {
			description = \"${LOAD}\";
			type = \"standalone\";
			arch = \"${ARCH}\";
			data = /incbin/(\"./${LOAD}.bin${SUFFIX}\");
			compression = \"${COMPRESSION}\";
			load = <0x"${LOAD_ADDR}">;"
		if [ "${COMPRESSION}" != "none" ]; then
			openssl dgst -sha256 -binary -out ${LOAD}.bin.digest ${LOAD}.bin
			${CMD} -k -f -9 ${LOAD}.bin
			RAW_SIZE=`wc -c ${LOAD}.bin | awk '{ printf "0x%x", $1 }'`
	echo "			raw-size = <${RAW_SIZE}>;
			digest {
				value = /incbin/(\"./${LOAD}.bin.digest\");
				algo = \"sha256\";
			};"
		fi
		echo "			hash {
				algo = \"sha256\";
			};
		};"

		LOADABLE_OTHER=${LOADABLE_OTHER}", \"${LOAD}\""
	done
}

function gen_header()
{
echo "
/*
 * Copyright (C) 2020 Rockchip Electronic Co.,Ltd
 *
 * Simple U-boot fit source file containing ATF/OP-TEE/U-Boot/dtb/MCU
 */

/dts-v1/;

/ {
	description = \"FIT Image with ATF/OP-TEE/U-Boot/MCU\";
	#address-cells = <1>;

	images {
"
}

function gen_arm64_configurations()
{
PLATFORM=`sed -n "/CONFIG_DEFAULT_DEVICE_TREE/p" .config | awk -F "=" '{ print $2 }' | tr -d '"'`
if grep  -q '^CONFIG_FIT_ENABLE_RSASSA_PSS_SUPPORT=y' .config ; then
	ALGO_PADDING="				padding = \"pss\";"
fi
echo "	};

	configurations {
		default = \"conf\";
		conf {
			description = \"${PLATFORM}\";
			rollback-index = <0x0>;
			firmware = \"atf-1\";
			loadables = \"uboot\"${LOADABLE_ATF}${LOADABLE_OPTEE}${LOADABLE_OTHER};
			${STANDALONE_MCU}
			fdt = \"fdt\"${PROP_KERN_DTB};
			signature {
				algo = \"sha256,rsa2048\";
				${ALGO_PADDING}
				key-name-hint = \"dev\";
				sign-images = \"fdt\", \"firmware\", \"loadables\"${STANDALONE_SIGN};
			};
		};
	};
};
"
}

function gen_arm_configurations()
{
PLATFORM=`sed -n "/CONFIG_DEFAULT_DEVICE_TREE/p" .config | awk -F "=" '{ print $2 }' | tr -d '"'`
if grep  -q '^CONFIG_FIT_ENABLE_RSASSA_PSS_SUPPORT=y' .config ; then
        ALGO_PADDING="                          padding = \"pss\";"
fi
echo "	};

	configurations {
		default = \"conf\";
		conf {
			description = \"${PLATFORM}\";
			rollback-index = <0x0>;
			firmware = \"optee\";
			loadables = \"uboot\"${LOADABLE_OTHER};
			${STANDALONE_MCU}
			fdt = \"fdt\"${PROP_KERN_DTB};
			signature {
				algo = \"sha256,rsa2048\";
				${ALGO_PADDING}
				key-name-hint = \"dev\";
				sign-images = \"fdt\", \"firmware\", \"loadables\"${STANDALONE_SIGN};
			};
		};
	};
};
"
}

